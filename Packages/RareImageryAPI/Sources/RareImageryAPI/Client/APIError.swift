import Foundation

public enum APIError: Error, Sendable, Equatable {
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case badRequest(message: String)
    case notFound
    case serverError(status: Int, message: String?)
    case network(URLError)
    case decode(String)
    case invalidConfiguration(String)
    case authCancelled
    case authFailed(String)

    public var isRetryable: Bool {
        switch self {
        case .network, .serverError, .rateLimited:
            return true
        default:
            return false
        }
    }
}
