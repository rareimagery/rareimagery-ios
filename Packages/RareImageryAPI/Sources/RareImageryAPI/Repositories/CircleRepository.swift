import Foundation

public actor CircleRepository {
    private let client: APIClient
    private let logger = APILogger(category: "CircleRepository")

    public init(client: APIClient) {
        self.client = client
    }

    /// Debounced X user search — exact handle lookup works on free-tier X API.
    public func searchUsers(query: String) async throws -> [XUserSummary] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        let endpoint = APIEndpoint(
            path: "/api/x/search-users",
            method: .get,
            queryItems: [URLQueryItem(name: "q", value: trimmed)],
            requiresAuth: true,
            contentType: nil,
            timeout: 12
        )

        let response = try await client.send(endpoint, as: XUserSearchResponse.self)
        return response.users
    }

    /// Everyone the caller follows on X, annotated with their RareImagery
    /// store slug when they have one. Powers the Friends tab; store-having
    /// friends arrive first (server-sorted).
    public func fetchFriends() async throws -> [FriendSummary] {
        let endpoint = APIEndpoint(
            path: "/api/social/friends",
            method: .get,
            requiresAuth: true,
            contentType: nil,
            timeout: 20
        )
        let response = try await client.send(endpoint, as: FriendsResponse.self)
        return response.friends
    }

    /// Curated follows + recent interactions from the BFF.
    public func fetchSuggestions(limit: Int = 24, includeRecent: Bool = true) async throws -> [XUserSummary] {
        let endpoint = APIEndpoint(
            path: "/api/social/circle/suggestions",
            method: .get,
            queryItems: [
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "include_recent", value: includeRecent ? "true" : "false"),
            ],
            requiresAuth: true,
            contentType: nil,
            timeout: 20
        )

        let response = try await client.send(endpoint, as: CircleSuggestionsResponse.self)
        return response.mergedUsers()
    }

    /// Replace the caller's Rare Circle pins on the server (max 24).
    public func updateCircle(handles: [String]) async throws -> CircleUpdateResponse {
        let payload = CircleUpdateRequest(handles: handles)
        let data = try JSONEncoder().encode(payload)
        let endpoint = APIEndpoint(
            path: "/api/social/circle",
            method: .put,
            body: data,
            requiresAuth: true,
            contentType: "application/json"
        )
        return try await client.send(endpoint, as: CircleUpdateResponse.self)
    }
}
