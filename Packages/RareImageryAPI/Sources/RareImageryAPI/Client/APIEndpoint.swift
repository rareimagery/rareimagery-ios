import Foundation

public struct APIEndpoint: Sendable {
    public let path: String
    public let method: HTTPMethod
    public let body: Data?
    public let queryItems: [URLQueryItem]
    public let requiresAuth: Bool
    public let contentType: String?
    public let timeout: TimeInterval?

    public init(
        path: String,
        method: HTTPMethod,
        body: Data? = nil,
        queryItems: [URLQueryItem] = [],
        requiresAuth: Bool = true,
        contentType: String? = "application/json",
        timeout: TimeInterval? = nil
    ) {
        self.path = path
        self.method = method
        self.body = body
        self.queryItems = queryItems
        self.requiresAuth = requiresAuth
        self.contentType = contentType
        self.timeout = timeout
    }

    public static func json<Body: Encodable>(
        path: String,
        method: HTTPMethod,
        body: Body,
        requiresAuth: Bool = true,
        timeout: TimeInterval? = nil
    ) throws -> APIEndpoint {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(body)
        return APIEndpoint(
            path: path,
            method: method,
            body: data,
            requiresAuth: requiresAuth,
            contentType: "application/json",
            timeout: timeout
        )
    }
}
