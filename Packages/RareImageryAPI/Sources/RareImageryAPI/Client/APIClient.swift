import Foundation

public actor APIClient {
    private let configuration: APIConfiguration
    private let session: URLSession
    private let keychain: KeychainStore
    private let logger = APILogger(category: "APIClient")

    private var refreshTask: Task<AuthTokenResponse, Error>?
    private var authEventHandlers = AuthEventHandlers()

    /// Injected by AuthManager (Task i2). When set, `request(...)` uses this
    /// instead of the Keychain Bearer for authenticated calls.
    private var tokenProvider: (@Sendable () async throws -> String)?

    /// When set, `refreshTokens()` uses Drupal `/oauth/token` instead of the BFF refresh route.
    private var oauthRefreshHandler: (@Sendable () async throws -> AuthTokenResponse)?

    public init(
        configuration: APIConfiguration,
        keychain: KeychainStore,
        urlSession: URLSession? = nil
    ) {
        self.configuration = configuration
        self.keychain = keychain
        if let urlSession {
            self.session = urlSession
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30
            config.timeoutIntervalForResource = 60
            config.waitsForConnectivity = true
            self.session = URLSession(configuration: config)
        }
    }

    public var config: APIConfiguration { configuration }

    public var endpoints: APIEnvironment.Endpoints { configuration.endpoints }

    public func setAuthEventHandlers(_ handlers: AuthEventHandlers) {
        authEventHandlers = handlers
    }

    public func setTokenProvider(_ provider: (@Sendable () async throws -> String)?) {
        tokenProvider = provider
    }

    public func setOAuthRefreshHandler(_ handler: (@Sendable () async throws -> AuthTokenResponse)?) {
        oauthRefreshHandler = handler
    }

    // MARK: - Generic request (Drupal JSON:API + /api/v1)

    /// Absolute-URL request used by JSON:API reads and rareimagery_api custom
    /// endpoints. Auth is optional; when `authenticated` and a token provider
    /// is set (Task i2), that token is used — otherwise falls back to Keychain.
    public func request<T: Decodable>(
        _ type: T.Type,
        url: URL,
        method: String = "GET",
        body: Data? = nil,
        contentType: String = "application/json",
        accept: String = "application/json",
        headers: [String: String] = [:],
        authenticated: Bool = true
    ) async throws -> T {
        let data = try await performRawRequest(
            url: url,
            method: method,
            body: body,
            contentType: contentType,
            accept: accept,
            headers: headers,
            authenticated: authenticated
        )
        do {
            return try JSONDecoder.rareImagery.decode(T.self, from: data)
        } catch {
            let snippet = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            throw APIError.decode("Failed to decode \(T.self): \(error.localizedDescription) — body=\(snippet)")
        }
    }

    /// Binary / custom-header request that returns raw response bytes after HTTP error mapping.
    public func performRawRequest(
        url: URL,
        method: String = "GET",
        body: Data? = nil,
        contentType: String = "application/json",
        accept: String = "application/json",
        headers: [String: String] = [:],
        authenticated: Bool = true
    ) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.httpBody = body
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        req.setValue(accept, forHTTPHeaderField: "Accept")
        for (key, value) in headers {
            req.setValue(value, forHTTPHeaderField: key)
        }

        if authenticated {
            let token = try await resolveAccessToken()
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response): (Data, URLResponse)
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

        try Self.throwIfDrupalAPIError(data: data, response: http)
        return data
    }

    /// Upload from a local file (preferred for large video / background sessions).
    public func uploadFile(
        fromFile fileURL: URL,
        to url: URL,
        method: String = "POST",
        contentType: String,
        accept: String = "application/vnd.api+json",
        headers: [String: String] = [:],
        authenticated: Bool = true,
        sessionOverride: URLSession? = nil
    ) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        req.setValue(accept, forHTTPHeaderField: "Accept")
        for (key, value) in headers {
            req.setValue(value, forHTTPHeaderField: key)
        }
        if authenticated {
            let token = try await resolveAccessToken()
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let uploadSession = sessionOverride ?? session
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await uploadSession.upload(for: req, fromFile: fileURL)
        } catch let urlError as URLError {
            throw APIError.network(urlError)
        } catch {
            throw APIError.network(URLError(.unknown))
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.serverError(status: -1, code: nil, message: "Non-HTTP response")
        }
        try Self.throwIfDrupalAPIError(data: data, response: http)
        return data
    }

    private func resolveAccessToken() async throws -> String {
        if let tokenProvider {
            return try await tokenProvider()
        }
        if let token = try await keychain.get(.accessToken) {
            return token
        }
        throw APIError.unauthorized
    }

    public func send<Response: Decodable>(
        _ endpoint: APIEndpoint,
        as: Response.Type = Response.self,
        retryOn401: Bool = true
    ) async throws -> Response {
        let request = try await buildRequest(for: endpoint)
        let (data, response) = try await perform(request, timeout: endpoint.timeout)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.serverError(status: -1, code: nil, message: "Non-HTTP response")
        }

        if http.statusCode == 401 && endpoint.requiresAuth && retryOn401 {
            logger.info("401 received — attempting token refresh and single retry")
            do {
                _ = try await refreshWithInvalidationOnFailure()
            } catch {
                throw APIError.unauthorized
            }
            let (retryData, retryResponse) = try await perform(
                try await buildRequest(for: endpoint),
                timeout: endpoint.timeout
            )
            guard let retryHTTP = retryResponse as? HTTPURLResponse else {
                throw APIError.serverError(status: -1, code: nil, message: "Non-HTTP response")
            }
            if retryHTTP.statusCode == 401 {
                await invokeSessionInvalidated()
                throw APIError.unauthorized
            }
            return try Self.decodeResponse(data: retryData, response: retryHTTP)
        }

        return try Self.decodeResponse(data: data, response: http)
    }

    /// Variant that returns the raw response body (for endpoints that we want to inspect/store).
    public func sendRaw(_ endpoint: APIEndpoint, retryOn401: Bool = true) async throws -> Data {
        let request = try await buildRequest(for: endpoint)
        let (data, response) = try await perform(request, timeout: endpoint.timeout)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.serverError(status: -1, code: nil, message: "Non-HTTP response")
        }
        if http.statusCode == 401 && endpoint.requiresAuth && retryOn401 {
            do {
                _ = try await refreshWithInvalidationOnFailure()
            } catch {
                throw APIError.unauthorized
            }
            let (retryData, retryResponse) = try await perform(
                try await buildRequest(for: endpoint),
                timeout: endpoint.timeout
            )
            guard let retryHTTP = retryResponse as? HTTPURLResponse else {
                throw APIError.serverError(status: -1, code: nil, message: "Non-HTTP response")
            }
            if retryHTTP.statusCode == 401 {
                await invokeSessionInvalidated()
                throw APIError.unauthorized
            }
            try Self.throwIfError(data: retryData, response: retryHTTP)
            return retryData
        }
        try Self.throwIfError(data: data, response: http)
        return data
    }

    // MARK: - Token Refresh

    /// Forces a token refresh — coalesces concurrent callers onto the same in-flight task.
    @discardableResult
    public func refreshTokens() async throws -> AuthTokenResponse {
        if let task = refreshTask { return try await task.value }
        let task = Task<AuthTokenResponse, Error> {
            defer { refreshTask = nil }
            return try await performRefresh()
        }
        refreshTask = task
        return try await task.value
    }

    private func refreshWithInvalidationOnFailure() async throws -> AuthTokenResponse {
        do {
            return try await refreshTokens()
        } catch {
            await invokeSessionInvalidated()
            throw error
        }
    }

    private func performRefresh() async throws -> AuthTokenResponse {
        if let oauthRefreshHandler {
            let tokens = try await oauthRefreshHandler()
            try await persist(tokens)
            if let handler = authEventHandlers.onTokensRefreshed {
                await handler(tokens)
            }
            return tokens
        }

        guard let refreshToken = try await keychain.get(.refreshToken) else {
            throw APIError.unauthorized
        }
        struct RefreshBody: Encodable { let refresh_token: String }
        let endpoint = try APIEndpoint.json(
            path: "/api/mobile/auth/refresh",
            method: .post,
            body: RefreshBody(refresh_token: refreshToken),
            requiresAuth: false
        )
        let request = try await buildRequest(for: endpoint)
        let (data, response) = try await perform(request, timeout: 15)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.serverError(status: -1, code: nil, message: "Non-HTTP response")
        }
        let tokens: AuthTokenResponse = try Self.decodeResponse(data: data, response: http)
        try await persist(tokens)
        if let handler = authEventHandlers.onTokensRefreshed {
            await handler(tokens)
        }
        return tokens
    }

    public func persist(_ tokens: AuthTokenResponse) async throws {
        try await keychain.set(tokens.accessToken, for: .accessToken)
        try await keychain.set(tokens.refreshToken, for: .refreshToken)
        let expiry = ISO8601DateFormatter().string(from: tokens.accessTokenExpiresAt)
        try await keychain.set(expiry, for: .accessTokenExpiry)
    }

    public func clearTokens() async throws {
        try await keychain.clearAll()
    }

    // MARK: - Internal request building

    private func buildRequest(for endpoint: APIEndpoint) async throws -> URLRequest {
        if endpoint.requiresAuth {
            try await ensureFreshAccessToken()
        }

        var components = URLComponents(url: configuration.baseURL.appendingPathComponent(endpoint.path), resolvingAgainstBaseURL: false)
        if !endpoint.queryItems.isEmpty { components?.queryItems = endpoint.queryItems }
        guard let url = components?.url else {
            throw APIError.invalidConfiguration("Could not construct URL for \(endpoint.path)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.httpBody = endpoint.body
        if let contentType = endpoint.contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if endpoint.requiresAuth {
            if let token = try await keychain.get(.accessToken) {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            } else {
                throw APIError.unauthorized
            }
        }
        return request
    }

    /// Proactive refresh — refresh ~60 s before access expiry.
    /// No-op for anonymous sessions (no refresh token).
    private func ensureFreshAccessToken() async throws {
        guard let refresh = try await keychain.get(.refreshToken), !refresh.isEmpty else {
            return
        }
        guard let access = try await keychain.get(.accessToken) else {
            _ = try await refreshWithInvalidationOnFailure()
            return
        }
        let needsRefresh: Bool
        if let claims = try? JWTDecoder.decode(access) {
            needsRefresh = claims.shouldRefresh()
        } else if let claims = try? JWTDecoder.decodePayload(access) {
            needsRefresh = claims.shouldRefresh()
        } else if let expiryString = try? await keychain.get(.accessTokenExpiry),
                  let expiry = ISO8601DateFormatter().date(from: expiryString) {
            needsRefresh = expiry.timeIntervalSinceNow <= 60
        } else {
            needsRefresh = true
        }
        if needsRefresh {
            _ = try await refreshWithInvalidationOnFailure()
        }
    }

    private func invokeSessionInvalidated() async {
        if let handler = authEventHandlers.onSessionInvalidated {
            await handler()
        }
    }

    private func perform(_ request: URLRequest, timeout: TimeInterval?) async throws -> (Data, URLResponse) {
        var req = request
        if let timeout = timeout { req.timeoutInterval = timeout }
        do {
            return try await session.data(for: req)
        } catch let urlError as URLError {
            throw APIError.network(urlError)
        } catch {
            throw APIError.network(URLError(.unknown))
        }
    }

    private static func decodeResponse<T: Decodable>(data: Data, response: HTTPURLResponse) throws -> T {
        try throwIfError(data: data, response: response)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            let snippet = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            throw APIError.decode("Failed to decode \(T.self): \(error.localizedDescription) — body=\(snippet)")
        }
    }

    /// Maps rareimagery_api HTTP errors (Drupal custom endpoints).
    private static func throwIfDrupalAPIError(data: Data, response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200..<300:
            return
        case 401:
            throw APIError.unauthorized
        case 403:
            throw APIError.forbidden
        case 404:
            throw APIError.notFound
        case 409:
            let item = (try? JSONDecoder().decode(APIErrorEnvelope.self, from: data))?.first
            throw APIError.conflict(
                code: item?.code ?? "conflict",
                detail: item?.detail ?? "Conflict."
            )
        case 422:
            let item = (try? JSONDecoder().decode(APIErrorEnvelope.self, from: data))?.first
            throw APIError.validation(
                code: item?.code ?? "validation_failed",
                detail: item?.detail ?? "Invalid input."
            )
        case 502:
            throw APIError.aiUnavailable
        default:
            throw APIError.serverError(status: response.statusCode, code: nil, message: nil)
        }
    }

    private static func throwIfError(data: Data, response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200..<300:
            return
        case 401:
            throw APIError.unauthorized
        case 403:
            throw APIError.forbidden
        case 404:
            throw APIError.notFound
        case 429:
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
            throw APIError.rateLimited(retryAfter: retryAfter)
        case 400..<500:
            let envelope = try? JSONDecoder().decode(MobileErrorResponse.self, from: data)
            let code = envelope?.code.flatMap(MobileErrorCode.init(rawValue:))
            let message = envelope?.displayMessage ?? "Bad request"
            throw APIError.badRequest(code: code, message: message)
        default:
            let envelope = try? JSONDecoder().decode(MobileErrorResponse.self, from: data)
            let code = envelope?.code.flatMap(MobileErrorCode.init(rawValue:))
            throw APIError.serverError(
                status: response.statusCode,
                code: code,
                message: envelope?.displayMessage
            )
        }
    }
}

extension JSONDecoder {
    /// Decoder for Drupal JSON:API + rareimagery_api bodies (ISO-8601 dates, no key remapping).
    public static let rareImagery: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
