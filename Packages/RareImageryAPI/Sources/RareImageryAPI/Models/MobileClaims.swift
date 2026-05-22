import Foundation

public struct MobileClaims: Codable, Sendable, Equatable {
    public let sub: String
    public let storeUuid: String?
    public let slug: String?
    public let handle: String?
    public let role: String?
    public let aud: String
    public let exp: Int
    public let iat: Int?

    public init(
        sub: String,
        storeUuid: String? = nil,
        slug: String? = nil,
        handle: String? = nil,
        role: String? = nil,
        aud: String,
        exp: Int,
        iat: Int? = nil
    ) {
        self.sub = sub
        self.storeUuid = storeUuid
        self.slug = slug
        self.handle = handle
        self.role = role
        self.aud = aud
        self.exp = exp
        self.iat = iat
    }

    enum CodingKeys: String, CodingKey {
        case sub
        case storeUuid = "store_uuid"
        case slug
        case handle
        case role
        case aud
        case exp
        case iat
    }

    public var expiresAt: Date { Date(timeIntervalSince1970: TimeInterval(exp)) }

    public var isExpired: Bool { expiresAt <= Date() }

    /// True when the token expires within the given window — caller should refresh.
    public func shouldRefresh(within window: TimeInterval = 120) -> Bool {
        expiresAt.timeIntervalSinceNow <= window
    }

    public static let expectedAudience = "mobile-access"

    public var hasExpectedAudience: Bool { aud == Self.expectedAudience }
}
