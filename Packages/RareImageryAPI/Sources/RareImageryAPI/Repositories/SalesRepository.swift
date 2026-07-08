import Foundation

/// The creator's sales system (Profile → Sales): revenue summary, order list,
/// order detail with shipping — read-only, imported from Drupal Commerce via
/// the BFF's per-creator /api/sales/* routes.
public actor SalesRepository {
    private let client: APIClient
    private let logger = APILogger(category: "SalesRepository")

    public init(client: APIClient) {
        self.client = client
    }

    // MARK: - GET /api/sales/summary

    public func summary(period: Int = 30) async throws -> SalesSummary {
        let endpoint = APIEndpoint(
            path: "/api/sales/summary",
            method: .get,
            queryItems: [URLQueryItem(name: "period", value: String(period))],
            requiresAuth: true,
            contentType: nil,
            timeout: 25
        )
        return try await client.send(endpoint)
    }

    // MARK: - GET /api/sales/orders

    public func listOrders(page: Int = 0, state: String? = nil) async throws -> OrdersPage {
        var query = [URLQueryItem(name: "page", value: String(page))]
        if let state { query.append(URLQueryItem(name: "state", value: state)) }
        let endpoint = APIEndpoint(
            path: "/api/sales/orders",
            method: .get,
            queryItems: query,
            requiresAuth: true,
            contentType: nil,
            timeout: 25
        )
        let response: OrdersPage = try await client.send(endpoint)
        logger.info("orders page \(page): \(response.orders.count)")
        return response
    }

    // MARK: - GET /api/sales/orders/{id}

    public func order(id: String) async throws -> OrderDetail {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let endpoint = APIEndpoint(
            path: "/api/sales/orders/\(encoded)",
            method: .get,
            requiresAuth: true,
            timeout: 25
        )
        return try await client.send(endpoint)
    }
}
