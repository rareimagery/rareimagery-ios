import Foundation

public struct MobileErrorResponse: Codable, Sendable, Equatable {
    public let error: String?
    public let code: String?
    public let message: String?

    public var displayMessage: String {
        message ?? error ?? "Something went wrong."
    }
}
