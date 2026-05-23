import Foundation

public actor APIClient {
    private let configuration: APIConfiguration
    private let session: URLSession
    private let keychain: KeychainStore
    private let logger = APILogger(category: "APIClient")

    private var refreshTask: Task<AuthTokenResponse, Error>?

    public init(configuration: APIConfiguration, keychain: KeychainStore) {
        self.configuration = configuration
        self.keychain = keychain
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
    }

    public var config: APIConfiguration { configuration }

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
                _ = try await refreshTokens()
            } catch {
                throw APIError.unauthorized
            }
            return try await send(endpoint, as: Response.self, retryOn401: false)
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
            _ = try await refreshTokens()
            return try await sendRaw(endpoint, retryOn401: false)
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

    private func performRefresh() async throws -> AuthTokenResponse {
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

    private static func throwIfError(data: Data, response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200..<300:
            return
        case 401:
            throw APIError.unauthorized
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
