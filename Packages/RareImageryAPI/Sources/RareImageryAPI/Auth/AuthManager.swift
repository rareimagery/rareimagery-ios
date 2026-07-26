import Foundation

/// Drupal simple_oauth authorization-code + PKCE + refresh.
///
/// Presentation (`ASWebAuthenticationSession`) stays in the app target
/// (`AuthCoordinator`); this actor owns URL building, token exchange,
/// Keychain persistence, and `validAccessToken()` for `APIClient`.
public actor AuthManager {
    public struct OAuthRequest: Sendable {
        public let authorizationURL: URL
        public let callbackScheme: String
    }

    private let configuration: APIConfiguration
    private let keychain: KeychainStore
    private let session: URLSession
    private let logger = APILogger(category: "AuthManager")

    private var cached: TokenSet?
    private var pendingVerifier: String?
    private var pendingState: String?
    private var refreshTask: Task<TokenSet, Error>?

    public init(
        configuration: APIConfiguration,
        keychain: KeychainStore,
        urlSession: URLSession = .shared
    ) {
        self.configuration = configuration
        self.keychain = keychain
        self.session = urlSession
    }

    /// Loads any persisted token pair into memory. Call once at app launch.
    @discardableResult
    public func restoreFromKeychain() async -> TokenSet? {
        if let set = cached { return set }
        guard
            let access = try? await keychain.get(.accessToken), !access.isEmpty,
            let refresh = try? await keychain.get(.refreshToken), !refresh.isEmpty
        else {
            return nil
        }
        let expiresAt: Date
        if let expiryString = try? await keychain.get(.accessTokenExpiry),
           let parsed = ISO8601DateFormatter().date(from: expiryString) {
            expiresAt = parsed
        } else {
            expiresAt = Date().addingTimeInterval(-1)
        }
        let set = TokenSet(accessToken: access, refreshToken: refresh, expiresAt: expiresAt)
        cached = set
        return set
    }

    public func hasSession() async -> Bool {
        (await restoreFromKeychain()) != nil
    }

    // MARK: - PKCE authorize

    public func startSignIn() throws -> OAuthRequest {
        guard configuration.isOAuthClientConfigured else {
            throw APIError.invalidConfiguration(
                "Drupal OAuth client ID is not set. Complete Phase D-A (create the " +
                "RareImagery iOS simple_oauth consumer) and put its UUID in " +
                "OAUTH_CLIENT_ID / Configuration/*.local.xcconfig."
            )
        }

        let verifier = PKCE.generateVerifier()
        let challenge = PKCE.challenge(for: verifier)
        let state = PKCE.generateVerifier(length: 43)
        pendingVerifier = verifier
        pendingState = state

        var comps = URLComponents(
            url: configuration.endpoints.oauthAuthorize,
            resolvingAgainstBaseURL: false
        )
        comps?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: configuration.oauthClientID),
            URLQueryItem(name: "redirect_uri", value: configuration.oauthRedirectURI),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]

        guard let url = comps?.url else {
            throw APIError.invalidConfiguration("Could not construct Drupal authorize URL")
        }

        logger.info("Built Drupal authorize URL — redirect_uri=\(configuration.oauthRedirectURI)")
        return OAuthRequest(
            authorizationURL: url,
            callbackScheme: configuration.xCallbackScheme
        )
    }

    /// Completes the ASWebAuthenticationSession callback: validate state, exchange code.
    @discardableResult
    public func completeSignIn(callbackURL: URL) async throws -> TokenSet {
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw APIError.authFailed("Malformed OAuth callback URL")
        }
        let items = components.queryItems ?? []
        if let err = items.first(where: { $0.name == "error" })?.value {
            let desc = items.first(where: { $0.name == "error_description" })?.value
            throw APIError.authFailed(desc ?? "OAuth error: \(err)")
        }
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw APIError.unauthorized
        }
        if let state = items.first(where: { $0.name == "state" })?.value,
           let expected = pendingState, state != expected {
            throw APIError.authFailed("State mismatch — possible CSRF, aborting")
        }
        guard let verifier = pendingVerifier else {
            throw APIError.authFailed("No PKCE verifier in memory — flow not started")
        }

        defer {
            pendingVerifier = nil
            pendingState = nil
        }

        let body = Self.form([
            "grant_type": "authorization_code",
            "client_id": configuration.oauthClientID,
            "redirect_uri": configuration.oauthRedirectURI,
            "code": code,
            "code_verifier": verifier,
        ])
        let set = try await tokenRequest(body: body)
        logger.info("Drupal OAuth complete — tokens persisted")
        return set
    }

    // MARK: - ADR-023 brokered sign-in (X via BFF → x_login at /oauth/token)

    /// Step 1 of the brokered flow: mint the Drupal-leg PKCE pair. The
    /// verifier stays in this actor; only the challenge travels (to the
    /// BFF, which binds it into the one-time x_login code).
    public func prepareBrokeredChallenge() throws -> String {
        guard configuration.isOAuthClientConfigured else {
            throw APIError.invalidConfiguration(
                "Drupal OAuth client ID is not set. Create the rareimagery-ios " +
                "simple_oauth consumer (T-014) and put its client_id in " +
                "OAUTH_CLIENT_ID / Configuration/*.local.xcconfig."
            )
        }
        let verifier = PKCE.generateVerifier()
        pendingVerifier = verifier
        pendingState = nil   // no authorize redirect in the brokered flow
        return PKCE.challenge(for: verifier)
    }

    /// Step 4: exchange the broker-issued one-time code at Drupal
    /// /oauth/token (grant_type=x_login) using the verifier from
    /// `prepareBrokeredChallenge`. Persists and returns the token set.
    @discardableResult
    public func completeBrokeredSignIn(drupalCode: String) async throws -> TokenSet {
        guard let verifier = pendingVerifier else {
            throw APIError.authFailed("No PKCE verifier in memory — flow not started")
        }
        defer {
            pendingVerifier = nil
            pendingState = nil
        }
        let body = Self.form([
            "grant_type": "x_login",
            "client_id": configuration.oauthClientID,
            "code": drupalCode,
            "code_verifier": verifier,
        ])
        let set = try await tokenRequest(body: body)
        logger.info("Brokered Drupal sign-in complete — tokens persisted")
        return set
    }

    // MARK: - Access token / refresh

    /// Returns a usable access token, refreshing when within 30s of expiry.
    public func validAccessToken() async throws -> String {
        guard let set = await restoreFromKeychain() else {
            throw APIError.unauthorized
        }
        if !set.isAccessExpiringSoon {
            return set.accessToken
        }
        let fresh = try await refreshTokens()
        return fresh.accessToken
    }

    @discardableResult
    public func refreshTokens() async throws -> TokenSet {
        if let task = refreshTask {
            return try await task.value
        }
        let task = Task<TokenSet, Error> {
            defer { refreshTask = nil }
            let existing: TokenSet?
            if let cached {
                existing = cached
            } else {
                existing = await restoreFromKeychain()
            }
            guard let set = existing else {
                throw APIError.unauthorized
            }
            let body = Self.form([
                "grant_type": "refresh_token",
                "client_id": configuration.oauthClientID,
                "refresh_token": set.refreshToken,
            ])
            return try await tokenRequest(body: body)
        }
        refreshTask = task
        do {
            return try await task.value
        } catch {
            await signOut()
            throw APIError.unauthorized
        }
    }

    public func signOut() async {
        cached = nil
        pendingVerifier = nil
        pendingState = nil
        try? await keychain.clearAll()
        logger.info("Signed out — OAuth tokens cleared from Keychain")
    }

    /// Installs this manager as the Bearer provider for `APIClient.request(...)`.
    public func install(on client: APIClient) async {
        await client.setTokenProvider { [weak self] in
            guard let self else { throw APIError.unauthorized }
            return try await self.validAccessToken()
        }
        await client.setOAuthRefreshHandler { [weak self] in
            guard let self else { throw APIError.unauthorized }
            let set = try await self.refreshTokens()
            return AuthTokenResponse(
                accessToken: set.accessToken,
                refreshToken: set.refreshToken,
                expiresIn: max(0, Int(set.expiresAt.timeIntervalSinceNow)),
                tokenType: "Bearer",
                creator: nil
            )
        }
    }

    // MARK: - Private

    private func tokenRequest(body: Data) async throws -> TokenSet {
        var req = URLRequest(url: configuration.endpoints.oauthToken)
        req.httpMethod = "POST"
        req.httpBody = body
        req.timeoutInterval = 20
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch let urlError as URLError {
            throw APIError.network(urlError)
        } catch {
            throw APIError.network(URLError(.unknown))
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.serverError(status: -1, code: nil, message: "Non-HTTP response")
        }
        guard http.statusCode == 200 else {
            let snippet = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            logger.warning("Token endpoint failed — status=\(http.statusCode) body=\(snippet)")
            let oauthError = try? JSONDecoder().decode(OAuthErrorBody.self, from: data)
            let message = oauthError?.userFacingMessage
                ?? "Sign-in failed (HTTP \(http.statusCode))."
            // Only wipe persisted tokens when a refresh fails — not during the
            // initial brokered x_login exchange (there may be nothing stored yet).
            if Self.formFields(from: body)["grant_type"] == "refresh_token" {
                await signOut()
            }
            throw APIError.authFailed(message)
        }

        let decoded: OAuthTokenResponse
        do {
            decoded = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
        } catch {
            throw APIError.decode("OAuth token response decode failed")
        }

        let set = decoded.asTokenSet()
        try await persist(set)
        return set
    }

    private func persist(_ set: TokenSet) async throws {
        cached = set
        try await keychain.set(set.accessToken, for: .accessToken)
        try await keychain.set(set.refreshToken, for: .refreshToken)
        try await keychain.set(
            ISO8601DateFormatter().string(from: set.expiresAt),
            for: .accessTokenExpiry
        )
    }

    private struct OAuthErrorBody: Decodable {
        let error: String?
        let errorDescription: String?
        let hint: String?

        enum CodingKeys: String, CodingKey {
            case error
            case errorDescription = "error_description"
            case hint
        }

        var userFacingMessage: String? {
            if let errorDescription, !errorDescription.isEmpty { return errorDescription }
            if let hint, !hint.isEmpty { return hint }
            if let error, !error.isEmpty { return error }
            return nil
        }
    }

    private static func formFields(from body: Data) -> [String: String] {
        guard let raw = String(data: body, encoding: .utf8) else { return [:] }
        var fields: [String: String] = [:]
        for pair in raw.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard let key = parts.first else { continue }
            let value = parts.count > 1 ? parts[1] : ""
            fields[key] = value.removingPercentEncoding ?? value
        }
        return fields
    }

    /// application/x-www-form-urlencoded body (RFC 1866 space-as-plus).
    static func form(_ fields: [String: String]) -> Data {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let pairs = fields.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }
        return pairs.joined(separator: "&").data(using: .utf8) ?? Data()
    }
}
