import Foundation

/// One creator store in the Shop directory, from `GET /api/discover/stores`.
/// Plain camelCase keys — APIClient decodes with `.convertFromSnakeCase`, which
/// leaves the BFF's already-camelCase output untouched.
public struct StoreSummary: Codable, Sendable, Equatable, Identifiable {
    public let handle: String
    public let displayName: String?
    public let bio: String?
    public let avatarUrl: String?
    public let bannerUrl: String?
    public let slug: String
    public let followerCount: Int?

    public var id: String { slug }
    public var avatarURL: URL? { avatarUrl.flatMap { URL(string: $0) } }
    public var bannerURL: URL? { bannerUrl.flatMap { URL(string: $0) } }
}

public struct StoresResponse: Decodable, Sendable {
    public let stores: [StoreSummary]
}
