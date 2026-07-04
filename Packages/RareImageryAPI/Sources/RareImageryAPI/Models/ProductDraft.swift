import Foundation

/// Result of `POST /api/vision/analyze` (resale-draft pipeline) per BFF agent handoff 2026-05-22.
/// Permissive decoding — most fields optional so the client tolerates server-side schema drift.
public struct ProductDraft: Codable, Sendable, Equatable {
    /// Market-value band the BFF attaches to video/valuation analyses
    /// (feat 2d4b927). All fields optional — older responses omit it.
    public struct EstimatedValue: Codable, Sendable, Equatable {
        public let low: Decimal?
        public let high: Decimal?
        public let currency: String?   // "USD"
        public let basis: String?      // resale_market | retail_new | auction_comp | unknown
        public let reasoning: String?

        public init(low: Decimal? = nil, high: Decimal? = nil, currency: String? = nil,
                    basis: String? = nil, reasoning: String? = nil) {
            self.low = low
            self.high = high
            self.currency = currency
            self.basis = basis
            self.reasoning = reasoning
        }
    }

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
    public let estimatedValue: EstimatedValue?

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
        flags: [String]? = nil,
        estimatedValue: EstimatedValue? = nil
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
        self.estimatedValue = estimatedValue
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

/// Analyze mode for `POST /api/vision/analyze` — routes Grok to valuation vs listing prompts.
public enum VisionAnalyzeMode: String, Codable, Sendable {
    case valuation
    case product
}

/// Price band returned at the top level in `product` mode responses.
public struct SuggestedPriceBand: Codable, Sendable, Equatable {
    public let low: Decimal?
    public let high: Decimal?
    public let currency: String?

    public init(low: Decimal? = nil, high: Decimal? = nil, currency: String? = nil) {
        self.low = low
        self.high = high
        self.currency = currency
    }
}

/// Top-level wrapper for `/api/vision/analyze`. `ok: false` carries a recoverable fallback draft.
public struct VisionResult: Codable, Sendable, Equatable {
    public let ok: Bool
    public let mode: VisionAnalyzeMode?
    public let draft: ProductDraft
    public let model: String?
    public let confidence: Double?
    /// Top-level market band — present in `valuation` mode (may also live on `draft`).
    public let estimatedValue: ProductDraft.EstimatedValue?
    /// Top-level listing band — present in `product` mode.
    public let suggestedPrice: SuggestedPriceBand?
    /// Single recommended list price (USD) when the BFF emits a point estimate.
    public let suggestedListPrice: Decimal?
    /// Narrative bullets (valuation insights or product selling points).
    public let insights: [String]?
    /// 0–10 scarcity signal when the model emits it (valuation mode).
    public let rarity: Double?
    /// Optional draft-claim token returned by anonymous analysis calls.
    /// When present, caller should persist to Keychain (.pendingDraftToken)
    /// so a later "Claim" can pass it through X OAuth callback.
    public let draftToken: String?

    public init(
        ok: Bool,
        mode: VisionAnalyzeMode? = nil,
        draft: ProductDraft,
        model: String? = nil,
        confidence: Double? = nil,
        estimatedValue: ProductDraft.EstimatedValue? = nil,
        suggestedPrice: SuggestedPriceBand? = nil,
        suggestedListPrice: Decimal? = nil,
        insights: [String]? = nil,
        rarity: Double? = nil,
        draftToken: String? = nil
    ) {
        self.ok = ok
        self.mode = mode
        self.draft = draft
        self.model = model
        self.confidence = confidence
        self.estimatedValue = estimatedValue
        self.suggestedPrice = suggestedPrice
        self.suggestedListPrice = suggestedListPrice
        self.insights = insights
        self.rarity = rarity
        self.draftToken = draftToken
    }
}
