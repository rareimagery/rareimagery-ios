import Foundation

/// Normalized X user row returned by `/api/x/search-users` and circle suggestions.
public struct XUserSummary: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let handle: String
    public let name: String
    public let avatar: String?
    public let followers: Int?
    public let followersFormatted: String?
    public let verified: Bool?

    public init(
        id: String,
        handle: String,
        name: String,
        avatar: String? = nil,
        followers: Int? = nil,
        followersFormatted: String? = nil,
        verified: Bool? = nil
    ) {
        self.id = id
        self.handle = handle
        self.name = name
        self.avatar = avatar
        self.followers = followers
        self.followersFormatted = followersFormatted
        self.verified = verified
    }

    public var avatarURL: URL? {
        guard let avatar, !avatar.isEmpty else { return nil }
        return URL(string: avatar)
    }
}

public struct XUserSearchResponse: Decodable, Sendable {
    public let users: [XUserSummary]
}

public struct CircleSuggestionsResponse: Decodable, Sendable {
    public struct InfluenceRow: Decodable, Sendable {
        public let xId: String
        public let username: String
        public let name: String
        public let profileImageUrl: String?

        enum CodingKeys: String, CodingKey {
            case xId = "x_id"
            case username, name
            case profileImageUrl = "profile_image_url"
        }
    }

    public struct InteractionRow: Decodable, Sendable {
        public let xId: String
        public let username: String
        public let name: String
        public let profileImageUrl: String?

        enum CodingKeys: String, CodingKey {
            case xId = "x_id"
            case username, name
            case profileImageUrl = "profile_image_url"
        }
    }

    public let topByInfluence: [InfluenceRow]
    public let recentInteractions: [InteractionRow]

    enum CodingKeys: String, CodingKey {
        case topByInfluence = "top_by_influence"
        case recentInteractions = "recent_interactions"
    }

    public func mergedUsers() -> [XUserSummary] {
        var byHandle: [String: XUserSummary] = [:]

        for row in recentInteractions {
            let key = row.username.lowercased()
            byHandle[key] = XUserSummary(
                id: row.xId,
                handle: row.username,
                name: row.name,
                avatar: row.profileImageUrl
            )
        }

        for row in topByInfluence {
            let key = row.username.lowercased()
            if byHandle[key] == nil {
                byHandle[key] = XUserSummary(
                    id: row.xId,
                    handle: row.username,
                    name: row.name,
                    avatar: row.profileImageUrl
                )
            }
        }

        return Array(byHandle.values).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

public struct CircleUpdateRequest: Encodable, Sendable {
    public struct Pin: Encodable, Sendable {
        public let xUsername: String
        public init(xUsername: String) { self.xUsername = xUsername }
    }

    public let pins: [Pin]

    public init(handles: [String]) {
        self.pins = handles.map { Pin(xUsername: $0) }
    }
}

public struct CircleUpdateResponse: Decodable, Sendable {
    public let ok: Bool
    public let count: Int?
}
