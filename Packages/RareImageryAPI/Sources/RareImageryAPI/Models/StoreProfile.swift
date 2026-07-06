import Foundation

/// The creator's public storefront profile, as returned by
/// `GET /api/stores/edit`. Source of the X avatar + banner captured at
/// account creation. Drives the Page tab (the public-facing store page).
///
/// Plain camelCase keys: APIClient decodes with `.convertFromSnakeCase`,
/// so avatar_url/banner_url arrive as avatarUrl/bannerUrl already.
public struct StoreProfile: Codable, Sendable, Equatable {
    public let storeName: String?
    public let displayName: String?
    public let bio: String?
    public let avatarUrl: String?
    public let bannerUrl: String?
    public let location: String?
    public let website: String?
    public let storeSlug: String?
    public let storeStatus: String?

    public var avatarURL: URL? { avatarUrl.flatMap { URL(string: $0) } }
    public var bannerURL: URL? { bannerUrl.flatMap { URL(string: $0) } }
}
