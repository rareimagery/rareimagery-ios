import Foundation

/// Coordinates the X OAuth 2.0 PKCE flow.
/// Mobile responsibility: generate verifier/challenge, build authorize URL, hold verifier in memory until the
/// callback returns the auth code, then exchange the code via AuthRepository (server completes with X).
public actor AuthService {
    private let configuration: APIConfiguration
    private let repository: AuthRepository
    private let client: APIClient
    private let logger = APILogger(category: "AuthService")

    private var pendingVerifier: String?
    private var pendingState: String?

    public init(configuration: APIConfiguration, repository: AuthRepository, client: APIClient) {
        self.configuration = configuration
        self.repository = repository
        self.client = client
    }

    public struct OAuthRequest: Sendable {
        public let authorizationURL: URL
        public let callbackScheme: String
    }

    /// Returns the URL to open in ASWebAuthenticationSession plus the callback scheme to listen for.
    public func startXAuth(scopes: [String] = ["tweet.read", "users.read", "offline.access"]) throws -> OAuthRequest {
        guard configuration.isXClientIDConfigured else {
            throw APIError.invalidConfiguration(
                "X OAuth Client ID is not set. Copy Configuration/Debug.local.xcconfig.example " +
                "to Debug.local.xcconfig and paste your X app's OAuth 2.0 Client ID " +
                "(developer.x.com → your app → Keys and tokens). The BFF needs the matching secret."
            )
        }
        let verifier = PKCE.generateVerifier()
        let challenge = PKCE.challenge(for: verifier)
        let state = PKCE.generateVerifier(length: 43)

        pendingVerifier = verifier
        pendingState = state

        var components = URLComponents(string: "https://x.com/i/oauth2/authorize")
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: configuration.xClientID),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]

        guard let url = components?.url else {
            throw APIError.invalidConfiguration("Could not construct X authorize URL")
        }

        logger.info("Built X authorize URL — redirect_uri=\(configuration.redirectURI)")
        return OAuthRequest(authorizationURL: url, callbackScheme: configuration.xCallbackScheme)
    }

    /// Process the callback URL returned by ASWebAuthenticationSession.
    /// Extracts the code, validates state, and exchanges via AuthRepository.
    /// If `draftToken` is non-nil it is forwarded to the x/callback for claim
    /// handoff (legacy authenticated-analyze path). `draftUuid` and
    /// `deviceId` are the current, additive contract for claiming a draft
    /// produced by the anonymous `/api/v1/vision/value` endpoint — both
    /// optional and independent of `draftToken`.
    public func completeXAuth(
        callbackURL: URL,
        draftToken: String? = nil,
        draftUuid: String? = nil,
        deviceId: String? = nil
    ) async throws -> AuthTokenResponse {
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw APIError.authFailed("Malformed callback URL")
        }
        let items = components.queryItems ?? []
        if let err = items.first(where: { $0.name == "error" })?.value {
            throw APIError.authFailed("X returned error: \(err)")
        }
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw APIError.authFailed("No authorization code in callback")
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

        let tokens = try await repository.completeOAuth(
            code: code,
            codeVerifier: verifier,
            redirectURI: configuration.redirectURI,
            draftToken: draftToken,
            draftUuid: draftUuid,
            deviceId: deviceId
        )
        try await client.persist(tokens)
        logger.info("X OAuth complete — token persisted")
        return tokens
    }

    public func signOut() async throws {
        try await client.clearTokens()
        logger.info("Signed out — tokens cleared from Keychain")
    }

    /// Link X enrichment to the signed-in creator (Phase E). Does not replace identity.
    public func linkXAccount(callbackURL: URL) async throws -> String {
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw APIError.authFailed("Malformed callback URL")
        }
        let items = components.queryItems ?? []
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw APIError.authFailed("No authorization code in callback")
        }
        guard let verifier = pendingVerifier else {
            throw APIError.authFailed("No PKCE verifier in memory — flow not started")
        }
        defer {
            pendingVerifier = nil
            pendingState = nil
        }
        struct LinkBody: Encodable {
            let code: String
            let codeVerifier: String
            let redirectUri: String
        }
        let payload = LinkBody(
            code: code,
            codeVerifier: verifier,
            redirectUri: configuration.redirectURI
        )
        struct LinkResponse: Decodable {
            let linked: Bool?
            let handle: String?
        }
        let endpoint = APIEndpoint(
            path: "/api/creator/link-x",
            method: .post,
            body: try JSONEncoder().encode(payload),
            requiresAuth: true,
            contentType: "application/json",
            timeout: 20
        )
        let response = try await client.send(endpoint, as: LinkResponse.self)
        let handle = response.handle ?? "x"
        logger.info("X account linked — @\(handle)")
        return handle
    }

    // MARK: - ADR-023 broker (X identity → Drupal-issued tokens)

    /// Response from the BFF's `/api/auth/x/exchange` broker endpoint.
    public struct DrupalExchange: Decodable, Sendable {
        public struct Creator: Decodable, Sendable {
            public let profileUuid: String
            public let storeUuid: String
            public let slug: String
            public let handle: String
            public let displayName: String?
            public let avatarUrl: String?
        }

        /// One-time x_login code to exchange at Drupal /oauth/token.
        public let drupalCode: String
        public let expiresIn: Int
        public let creator: Creator?

        enum CodingKeys: String, CodingKey {
            case drupalCode = "drupal_code"
            case expiresIn = "expires_in"
            case creator
        }
    }

    /// ADR-023 step 3: swap the X authorization code for a one-time Drupal
    /// login code. Same callback parsing + CSRF/state discipline as
    /// `completeXAuth`, but the BFF responds with a `drupal_code` instead
    /// of minting its own session — the caller finishes at /oauth/token
    /// via `AuthManager.completeBrokeredSignIn`.
    ///
    /// `drupalCodeChallenge` is the SECOND PKCE challenge (Drupal leg),
    /// generated by AuthManager; its verifier never touches this actor.
    public func exchangeForDrupalCode(
        callbackURL: URL,
        drupalCodeChallenge: String,
        clientId: String
    ) async throws -> DrupalExchange {
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw APIError.authFailed("Malformed callback URL")
        }
        let items = components.queryItems ?? []
        if let err = items.first(where: { $0.name == "error" })?.value {
            throw APIError.authFailed("X returned error: \(err)")
        }
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw APIError.authFailed("No authorization code in callback")
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

        struct ExchangeRequest: Encodable {
            let code: String
            let codeVerifier: String
            let redirectUri: String
            let clientId: String
            let drupalCodeChallenge: String

            enum CodingKeys: String, CodingKey {
                case code
                case codeVerifier
                case redirectUri
                case clientId = "client_id"
                case drupalCodeChallenge = "drupal_code_challenge"
            }
        }

        let payload = ExchangeRequest(
            code: code,
            codeVerifier: verifier,
            redirectUri: configuration.redirectURI,
            clientId: clientId,
            drupalCodeChallenge: drupalCodeChallenge
        )
        let body = try JSONEncoder().encode(payload)
        let endpoint = APIEndpoint(
            path: "/api/auth/x/exchange",
            method: .post,
            body: body,
            requiresAuth: false,   // this IS the sign-in
            contentType: "application/json",
            timeout: 20
        )
        let exchange = try await client.send(endpoint, as: DrupalExchange.self)
        logger.info("Broker exchange complete — drupal_code received (expires in \(exchange.expiresIn)s)")
        return exchange
    }

    // MARK: - Apple / Google broker (ADR-023 multi-provider)

    public struct ProviderSlugRequired: Sendable {
        public let ticket: String
        public let suggestedSlug: String?
        public let message: String
    }

    public enum ProviderExchangeOutcome: Sendable {
        case completed(DrupalExchange)
        case needsSlug(ProviderSlugRequired)
    }

    public func exchangeAppleForDrupalCode(
        identityToken: String,
        fullName: String?,
        drupalCodeChallenge: String,
        clientId: String
    ) async throws -> ProviderExchangeOutcome {
        struct Request: Encodable {
            let identityToken: String
            let fullName: String?
            let clientId: String
            let drupalCodeChallenge: String

            enum CodingKeys: String, CodingKey {
                case identityToken
                case fullName
                case clientId = "client_id"
                case drupalCodeChallenge = "drupal_code_challenge"
            }
        }
        let payload = Request(
            identityToken: identityToken,
            fullName: fullName,
            clientId: clientId,
            drupalCodeChallenge: drupalCodeChallenge
        )
        return try await postProviderExchange(
            path: "/api/auth/apple/exchange",
            body: try JSONEncoder().encode(payload)
        )
    }

    public func exchangeGoogleForDrupalCode(
        identityToken: String,
        drupalCodeChallenge: String,
        clientId: String
    ) async throws -> ProviderExchangeOutcome {
        struct Request: Encodable {
            let identityToken: String
            let clientId: String
            let drupalCodeChallenge: String

            enum CodingKeys: String, CodingKey {
                case identityToken
                case clientId = "client_id"
                case drupalCodeChallenge = "drupal_code_challenge"
            }
        }
        let payload = Request(
            identityToken: identityToken,
            clientId: clientId,
            drupalCodeChallenge: drupalCodeChallenge
        )
        return try await postProviderExchange(
            path: "/api/auth/google/exchange",
            body: try JSONEncoder().encode(payload)
        )
    }

    public func completeProviderSlugPick(
        path: String,
        ticket: String,
        slug: String,
        drupalCodeChallenge: String,
        clientId: String
    ) async throws -> DrupalExchange {
        struct Request: Encodable {
            let ticket: String
            let slug: String
            let clientId: String
            let drupalCodeChallenge: String

            enum CodingKeys: String, CodingKey {
                case ticket, slug
                case clientId = "client_id"
                case drupalCodeChallenge = "drupal_code_challenge"
            }
        }
        let payload = Request(
            ticket: ticket,
            slug: slug,
            clientId: clientId,
            drupalCodeChallenge: drupalCodeChallenge
        )
        let outcome = try await postProviderExchange(
            path: path,
            body: try JSONEncoder().encode(payload)
        )
        switch outcome {
        case .completed(let exchange):
            return exchange
        case .needsSlug:
            throw APIError.authFailed("Slug pick was rejected — please try a different slug.")
        }
    }

    private struct NeedsSlugResponse: Decodable {
        struct ErrorBody: Decodable {
            let code: String?
            let message: String?
        }
        let error: ErrorBody?
        let suggestedSlug: String?
        let ticket: String?

        enum CodingKeys: String, CodingKey {
            case error
            case suggestedSlug
            case ticket
        }
    }

    private func postProviderExchange(path: String, body: Data) async throws -> ProviderExchangeOutcome {
        var request = URLRequest(url: configuration.baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let urlError as URLError {
            throw APIError.network(urlError)
        } catch {
            throw APIError.network(URLError(.unknown))
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.serverError(status: -1, code: nil, message: "Non-HTTP response")
        }

        if http.statusCode == 409,
           let needs = try? JSONDecoder().decode(NeedsSlugResponse.self, from: data),
           needs.error?.code == MobileErrorCode.needsSlug.rawValue,
           let ticket = needs.ticket, !ticket.isEmpty {
            return .needsSlug(ProviderSlugRequired(
                ticket: ticket,
                suggestedSlug: needs.suggestedSlug,
                message: needs.error?.message ?? "Choose a storefront slug."
            ))
        }

        if http.statusCode == 200,
           let exchange = try? JSONDecoder().decode(DrupalExchange.self, from: data),
           !exchange.drupalCode.isEmpty {
            logger.info("Provider exchange complete — drupal_code received")
            return .completed(exchange)
        }

        if let envelope = try? JSONDecoder().decode(MobileErrorResponse.self, from: data),
           let code = envelope.code.flatMap(MobileErrorCode.init(rawValue:)) {
            throw APIError.badRequest(code: code, message: envelope.displayMessage)
        }
        throw APIError.serverError(
            status: http.statusCode,
            code: nil,
            message: String(data: data, encoding: .utf8)
        )
    }
}
