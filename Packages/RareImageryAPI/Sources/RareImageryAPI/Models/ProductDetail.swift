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
    /// All product images (the GET route's `image_urls`). First entry is the
    /// hero; `thumbnail` is a convenience alias for it.
    public let imageUrls: [String]?
    /// Capture video URL — reserved for Phase 2 (the BFF doesn't return it
    /// yet, so this decodes to nil today). The detail view swaps its hero
    /// image for a player once this is populated.
    public let videoUrl: String?
    public let category: ProductCategory?
    public let condition: ProductCondition?
    public let tags: [String]?
    public let createdAt: String?
    public let updatedAt: String?

    public var id: String { uuid }
    public var isPublished: Bool { status == "published" }

    /// Best available hero image: explicit thumbnail, else the first image.
    public var heroImageUrl: String? { thumbnail ?? imageUrls?.first }

    // APIClient decodes with .convertFromSnakeCase, so the GET route's
    // `price_usd` arrives as `priceUsd`, `thumbnail_url` as `thumbnailUrl`,
    // `image_urls` as `imageUrls`, `video_url` as `videoUrl`. Map the first
    // two onto `price`/`thumbnail` so the editor prefills Grok's estimated
    // price (stored on the draft variation) instead of nil.
    enum CodingKeys: String, CodingKey {
        case uuid, title, description, status, category, condition, tags
        case price = "priceUsd"
        case thumbnail = "thumbnailUrl"
        case imageUrls, videoUrl
        case storefrontUrl, createdAt, updatedAt
    }
}
