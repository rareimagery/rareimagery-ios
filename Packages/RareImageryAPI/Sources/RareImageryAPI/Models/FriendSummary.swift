import Foundation

/// One person the caller follows on X, from `GET /api/social/friends`.
/// `storeSlug` is non-nil when they have an approved RareImagery store —
/// the Friends tab links those rows into the native store page.
public struct FriendSummary: Codable, Sendable, Equatable, Identifiable {
    public let id: String          // X user id
    public let handle: String
    public let name: String
    public let avatarUrl: String?
    public let storeSlug: String?

    public var avatarURL: URL? { avatarUrl.flatMap { URL(string: $0) } }
    public var hasStore: Bool { !(storeSlug ?? "").isEmpty }
}

public struct FriendsResponse: Decodable, Sendable {
    public let friends: [FriendSummary]
}
