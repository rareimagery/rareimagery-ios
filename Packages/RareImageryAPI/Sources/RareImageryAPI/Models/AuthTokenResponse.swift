import Foundation

public struct AuthTokenResponse: Codable, Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresIn: Int

    public init(accessToken: String, refreshToken: String, expiresIn: Int) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresIn = expiresIn
    }

    public var accessTokenExpiresAt: Date {
        Date().addingTimeInterval(TimeInterval(expiresIn))
    }
}
