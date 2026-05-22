import Foundation

/// Result of POST /api/products/from-images — Grok Vision's analysis of a hero photo.
/// Field names are deliberately permissive (most optional) so the client tolerates
/// backend additions without decode failures.
public struct ProductDraft: Codable, Sendable, Equatable, Identifiable {
    public let uuid: String
    public let title: String
    public let description: String?
    public let suggestedPrice: Decimal?
    public let category: ProductCategory?
    public let condition: ProductCondition?
    public let tags: [String]?
    public let confidence: Double?
    public let heroImageURL: String?

    public var id: String { uuid }

    enum CodingKeys: String, CodingKey {
        case uuid
        case title
        case description
        case suggestedPrice = "suggested_price"
        case category
        case condition
        case tags
        case confidence
        case heroImageURL = "hero_image_url"
    }
}
