import Foundation

// MARK: - POST /api/products/from-images  (Phase 4 — persist path)
//
// Unlike `/api/vision/analyze` (analysis-only, camelCase), this endpoint runs
// Grok analyze AND creates a Drupal product, returning `draft_id` — the product
// UUID the app then PATCHes and publishes. The BFF contract is **snake_case**
// on both request and response (`src/lib/mobile/from-images.ts`).
//
// Request encoding is handled by `APIEndpoint.json` (keyEncodingStrategy =
// .convertToSnakeCase), so the Swift camelCase property names below serialize
// to `image_urls`, `hero_only`, etc. The response, however, is decoded via
// `JSONDecoder.rareImagery`, which does NOT convert snake_case — so every
// response model carries explicit `CodingKeys`.

/// Request body for `POST /api/products/from-images`.
/// Serialized with `.convertToSnakeCase` (via `APIEndpoint.json`).
public struct FromImagesRequest: Encodable, Sendable {
    /// JPEG base64 data URLs (`data:image/jpeg;base64,…`), 1–4 entries.
    public let imageUrls: [String]
    /// When true (or omitted server-side) only the first image is analyzed.
    public let heroOnly: Bool
    public let voiceTranscript: String?
    /// One of the BFF `product_intent` enum values ("resell" | "design_merch" | …).
    public let productIntent: String?
    /// Storefront UUID from the caller's JWT; the server rejects a mismatch.
    public let storeUuid: String?
    public let metadata: Metadata?

    public struct Metadata: Encodable, Sendable {
        /// "photo" | "video" — BFF telemetry (`metadata.source`).
        public let source: String?
        public init(source: String?) { self.source = source }
    }

    public init(
        imageUrls: [String],
        heroOnly: Bool,
        voiceTranscript: String? = nil,
        productIntent: String? = nil,
        storeUuid: String? = nil,
        metadata: Metadata? = nil
    ) {
        self.imageUrls = imageUrls
        self.heroOnly = heroOnly
        self.voiceTranscript = voiceTranscript
        self.productIntent = productIntent
        self.storeUuid = storeUuid
        self.metadata = metadata
    }
}

/// The mobile capture draft the BFF returns alongside `draft_id`
/// (`MobileProductDraft` in `from-images.ts`). Permissive — most fields
/// optional so the client tolerates server-side schema drift.
public struct MobileCaptureDraft: Decodable, Sendable, Equatable {
    public struct EstimatedValue: Decodable, Sendable, Equatable {
        public let low: Decimal?
        public let high: Decimal?
        public let currency: String?
        public let basis: String?
        public let reasoning: String?
    }

    public let confidence: Double?
    public let title: String
    public let description: String?
    public let category: String?
    public let subcategory: String?
    public let condition: String?
    public let conditionNotes: String?
    public let specs: [String: String]?
    public let suggestedPriceUsd: Decimal?
    public let priceReasoning: String?
    public let estimatedValue: EstimatedValue?
    public let tags: [String]?
    public let flags: [String: Bool]?

    enum CodingKeys: String, CodingKey {
        case confidence, title, description, category, subcategory, condition
        case conditionNotes = "condition_notes"
        case specs
        case suggestedPriceUsd = "suggested_price_usd"
        case priceReasoning = "price_reasoning"
        case estimatedValue = "estimated_value"
        case tags, flags
    }

    public init(
        confidence: Double? = nil,
        title: String,
        description: String? = nil,
        category: String? = nil,
        subcategory: String? = nil,
        condition: String? = nil,
        conditionNotes: String? = nil,
        specs: [String: String]? = nil,
        suggestedPriceUsd: Decimal? = nil,
        priceReasoning: String? = nil,
        estimatedValue: EstimatedValue? = nil,
        tags: [String]? = nil,
        flags: [String: Bool]? = nil
    ) {
        self.confidence = confidence
        self.title = title
        self.description = description
        self.category = category
        self.subcategory = subcategory
        self.condition = condition
        self.conditionNotes = conditionNotes
        self.specs = specs
        self.suggestedPriceUsd = suggestedPriceUsd
        self.priceReasoning = priceReasoning
        self.estimatedValue = estimatedValue
        self.tags = tags
        self.flags = flags
    }
}

/// Response of `POST /api/products/from-images` on the signed-in path.
/// `draftId` is the created Drupal product UUID — PATCH / publish target.
public struct FromImagesResponse: Decodable, Sendable, Equatable {
    public let draftId: String
    public let draft: MobileCaptureDraft
    public let previewImageUrl: String?
    public let processingTimeMs: Int?

    enum CodingKeys: String, CodingKey {
        case draftId = "draft_id"
        case draft
        case previewImageUrl = "preview_image_url"
        case processingTimeMs = "processing_time_ms"
    }

    public init(
        draftId: String,
        draft: MobileCaptureDraft,
        previewImageUrl: String? = nil,
        processingTimeMs: Int? = nil
    ) {
        self.draftId = draftId
        self.draft = draft
        self.previewImageUrl = previewImageUrl
        self.processingTimeMs = processingTimeMs
    }
}

// MARK: - Bridge to the existing draft-review UI

public extension MobileCaptureDraft {
    /// Map to the analyze-flow `ProductDraft` so screens built around the
    /// vision draft (DraftPreview, CaptureResultView) can render a
    /// from-images result unchanged. Category/condition are left nil — the
    /// review surface re-reads canonical values from `GET /api/products/{uuid}`.
    func toProductDraft() -> ProductDraft {
        let low = estimatedValue?.low ?? suggestedPriceUsd
        let high = estimatedValue?.high ?? suggestedPriceUsd
        return ProductDraft(
            title: title,
            summary: description,
            description: description,
            category: nil,
            condition: nil,
            brand: specs?["brand"],
            suggestedPriceLow: low,
            suggestedPriceHigh: high,
            tags: tags,
            handmade: flags?["appears_handmade"],
            confidence: confidence,
            flags: flags.map { Array($0.filter { $0.value }.keys).sorted() },
            estimatedValue: estimatedValue.map {
                ProductDraft.EstimatedValue(
                    low: $0.low,
                    high: $0.high,
                    currency: $0.currency,
                    basis: $0.basis,
                    reasoning: $0.reasoning
                )
            }
        )
    }
}
