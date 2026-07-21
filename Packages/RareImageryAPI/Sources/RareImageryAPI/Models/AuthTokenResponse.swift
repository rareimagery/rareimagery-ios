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

        public init(
            profileUuid: String? = nil,
            storeUuid: String? = nil,
            slug: String? = nil,
            handle: String? = nil,
            displayName: String? = nil,
            avatarUrl: String? = nil,
            role: String? = nil
        ) {
            self.profileUuid = profileUuid
            self.storeUuid = storeUuid
            self.slug = slug
            self.handle = handle
            self.displayName = displayName
            self.avatarUrl = avatarUrl
            self.role = role
        }
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
