import Foundation

/// Returned by `GET /api/products/[uuid]` and the CRUD variants.
/// Field names lean permissive so the client doesn't break when the BFF adds keys.
public struct ProductDetail: Codable, Sendable, Equatable, Identifiable {
    public let uuid: String
    public let title: String?
    public let description: String?
    public let price: Decimal?
    public let status: String?
    public let thumbnail: String?
    public let storefrontUrl: String?
    public let category: ProductCategory?
    public let condition: ProductCondition?
    public let tags: [String]?
    public let createdAt: String?
    public let updatedAt: String?

    public var id: String { uuid }
    public var isPublished: Bool { status == "published" }

    // APIClient decodes with .convertFromSnakeCase, so the GET route's
    // `price_usd` arrives as `priceUsd` and `thumbnail_url` as `thumbnailUrl`.
    // Map them onto `price`/`thumbnail` so the editor prefills Grok's
    // estimated price (stored on the draft variation) instead of nil.
    enum CodingKeys: String, CodingKey {
        case uuid, title, description, status, category, condition, tags
        case price = "priceUsd"
        case thumbnail = "thumbnailUrl"
        case storefrontUrl, createdAt, updatedAt
    }
}
