import Foundation

/// Result of `POST /api/vision/analyze` (resale-draft pipeline) per BFF agent handoff 2026-05-22.
/// Permissive decoding — most fields optional so the client tolerates server-side schema drift.
public struct ProductDraft: Codable, Sendable, Equatable {
    public let title: String
    public let summary: String?
    public let description: String?
    public let category: ProductCategory?
    public let condition: ProductCondition?
    public let brand: String?
    public let suggestedPriceLow: Decimal?
    public let suggestedPriceHigh: Decimal?
    public let tags: [String]?
    public let handmade: Bool?
    public let confidence: Double?
    public let flags: [String]?

    public init(
        title: String,
        summary: String? = nil,
        description: String? = nil,
        category: ProductCategory? = nil,
        condition: ProductCondition? = nil,
        brand: String? = nil,
        suggestedPriceLow: Decimal? = nil,
        suggestedPriceHigh: Decimal? = nil,
        tags: [String]? = nil,
        handmade: Bool? = nil,
        confidence: Double? = nil,
        flags: [String]? = nil
    ) {
        self.title = title
        self.summary = summary
        self.description = description
        self.category = category
        self.condition = condition
        self.brand = brand
        self.suggestedPriceLow = suggestedPriceLow
        self.suggestedPriceHigh = suggestedPriceHigh
        self.tags = tags
        self.handmade = handmade
        self.confidence = confidence
        self.flags = flags
    }

    public var priceDisplay: String? {
        switch (suggestedPriceLow, suggestedPriceHigh) {
        case let (.some(lo), .some(hi)) where lo != hi:
            return "$\(lo)–$\(hi)"
        case let (.some(lo), _):
            return "$\(lo)"
        case let (_, .some(hi)):
            return "$\(hi)"
        default:
            return nil
        }
    }
}

/// Top-level wrapper for `/api/vision/analyze`. `ok: false` carries a recoverable fallback draft.
public struct VisionResult: Codable, Sendable, Equatable {
    public let ok: Bool
    public let draft: ProductDraft
    public let model: String?
}
