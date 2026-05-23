import Foundation

/// Response from `POST /api/mobile/auth/x/callback` and `POST /api/mobile/auth/refresh`.
/// Shape per CLAUDE.md §2.2.
public struct AuthTokenResponse: Codable, Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresIn: Int
    public let tokenType: String?
    public let creator: Creator?

    public struct Creator: Codable, Sendable, Equatable {
        public let profileUuid: String?
        public let storeUuid: String?
        public let slug: String?
        public let handle: String?
        public let displayName: String?
        public let avatarUrl: String?
        public let role: String?
    }

    public init(
        accessToken: String,
        refreshToken: String,
        expiresIn: Int,
        tokenType: String? = "Bearer",
        creator: Creator? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresIn = expiresIn
        self.tokenType = tokenType
        self.creator = creator
    }

    public var accessTokenExpiresAt: Date {
        Date().addingTimeInterval(TimeInterval(expiresIn))
    }
}
