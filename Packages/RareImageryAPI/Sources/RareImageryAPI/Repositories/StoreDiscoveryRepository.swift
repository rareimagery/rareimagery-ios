import Foundation

/// Buyer-facing store discovery for the Shop tab. Lists approved creator stores
/// and loads a single store's profile + published products. Read-only; requires
/// a mobile-access token (the BFF gates `/api/discover/*` with
/// `requireSessionOrMobile`).
public actor StoreDiscoveryRepository {
    private let client: APIClient
    private let logger = APILogger(category: "StoreDiscoveryRepository")

    public init(client: APIClient) {
        self.client = client
    }

    // MARK: - GET /api/discover/stores

    /// Every approved creator store, for the Shop directory.
    public func listStores() async throws -> [StoreSummary] {
        let endpoint = APIEndpoint(
            path: "/api/discover/stores",
            method: .get,
            requiresAuth: true,
            timeout: 20
        )
        let response: StoresResponse = try await client.send(endpoint)
        logger.info("listStores: \(response.stores.count) stores")
        return response.stores
    }

    // MARK: - GET /api/discover/stores/{slug}

    /// One store's hero profile + published products, for the native store page.
    public func store(slug: String) async throws -> StoreDetail {
        let encoded = slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? slug
        let endpoint = APIEndpoint(
            path: "/api/discover/stores/\(encoded)",
            method: .get,
            requiresAuth: true,
            timeout: 20
        )
        return try await client.send(endpoint)
    }
}
