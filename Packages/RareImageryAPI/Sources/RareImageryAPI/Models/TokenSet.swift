import Foundation

/// Access + refresh pair persisted in Keychain for Drupal simple_oauth.
public struct TokenSet: Codable, Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date

    public init(accessToken: String, refreshToken: String, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    public var isAccessExpiringSoon: Bool {
        expiresAt <= Date().addingTimeInterval(30)
    }
}

/// Raw token endpoint body from simple_oauth `/oauth/token`.
struct OAuthTokenResponse: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let tokenType: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }

    func asTokenSet(now: Date = Date()) -> TokenSet {
        TokenSet(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: now.addingTimeInterval(TimeInterval(expiresIn))
        )
    }

    func asAuthTokenResponse() -> AuthTokenResponse {
        AuthTokenResponse(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresIn: expiresIn,
            tokenType: tokenType ?? "Bearer",
            creator: nil
        )
    }
}
