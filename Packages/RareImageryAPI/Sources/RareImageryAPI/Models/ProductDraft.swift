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
