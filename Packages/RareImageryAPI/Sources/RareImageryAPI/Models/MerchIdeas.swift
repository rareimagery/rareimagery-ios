import Foundation

/// Request body for `POST /api/vision/merch-ideas`. CamelCase keys —
/// the request must be encoded with `keyEncodingStrategy = .useDefaultKeys`
/// (the SPM default is `.convertToSnakeCase`, which would mangle these).
public struct MerchIdeasRequest: Encodable, Sendable {
    public let imageUrls: [String]                 // 1..4, data URL or HTTPS, ≤20MB each
    public let productIntent: MerchProductIntent?  // default .designMerch (server-side)
    public let productType: MerchProductType?      // optional Grok hint
    public let voiceTranscript: String?            // ≤500 chars
    public let featureFriends: [String]?           // ≤24 X handles (no @, lowercased)
    public let heroOnly: Bool?                     // default true (analyze first image only)

    public init(
        imageUrls: [String],
        productIntent: MerchProductIntent? = .designMerch,
        productType: MerchProductType? = nil,
        voiceTranscript: String? = nil,
        featureFriends: [String]? = nil,
        heroOnly: Bool? = true
    ) {
        self.imageUrls = imageUrls
        self.productIntent = productIntent
        self.productType = productType
        self.voiceTranscript = voiceTranscript
        self.featureFriends = featureFriends
        self.heroOnly = heroOnly
    }
}

public enum MerchProductIntent: String, Codable, Sendable {
    case designMerch = "design_merch"
    case resale
}

public enum MerchProductType: String, Codable, Sendable {
    case physical
    case digital
}

/// Response from `POST /api/vision/merch-ideas`. Always HTTP 200 unless
/// auth/validation/rate-limit fail — `ok: false` is the degraded-vendor
/// path with a populated fallback `ideas[]`.
public struct MerchIdeasResponse: Decodable, Sendable, Equatable {
    public let ok: Bool
    public let ideas: [MerchIdeaDraft]
    public let primaryRecommendation: Int
    public let confidence: Double
    public let model: Model
    public let processingTimeMs: Int
    public let warnings: [String]?
    public let error: String?

    public enum Model: String, Decodable, Sendable {
        case grokVision = "grok-2-vision-1212"
        case claudeSonnet = "claude-sonnet-4-6"
        case fallback
    }
}

public struct MerchIdeaDraft: Decodable, Sendable, Equatable, Identifiable {
    /// Client-side identity; the server doesn't emit `id`. Excluded from
    /// `CodingKeys` so the synthesized decoder uses the default UUID.
    public var id: UUID = UUID()

    public let title: String                     // ≤80 chars
    public let description: String               // ≤500 chars
    public let suggestedPrompt: String           // ≤500 chars, Grok-Imagine ready
    public let category: Category                // one of 8 controlled values
    public let tags: [String]                    // ≤8, lowercase kebab-case
    public let estimatedPrice: PriceRange
    public let whyItWorks: String                // ≤300 chars
    public let flags: [String]?                  // e.g. ["needs_review", "low_confidence"]

    public enum Category: String, Decodable, Sendable {
        case tShirt = "t-shirt"
        case hoodie
        case sticker
        case mug
        case toteBag = "tote-bag"
        case cap
        case print
        case digitalDownload = "digital-download"

        public var displayName: String {
            switch self {
            case .tShirt: return "T-Shirt"
            case .hoodie: return "Hoodie"
            case .sticker: return "Sticker"
            case .mug: return "Mug"
            case .toteBag: return "Tote Bag"
            case .cap: return "Cap"
            case .print: return "Print"
            case .digitalDownload: return "Digital Download"
            }
        }
    }

    public struct PriceRange: Decodable, Sendable, Equatable {
        public let low: Double?
        public let high: Double?

        public var display: String? {
            switch (low, high) {
            case let (.some(lo), .some(hi)) where lo != hi:
                return "$\(Int(lo))–$\(Int(hi))"
            case let (.some(lo), _):
                return "$\(Int(lo))"
            case let (_, .some(hi)):
                return "$\(Int(hi))"
            default:
                return nil
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case title, description, suggestedPrompt, category, tags
        case estimatedPrice, whyItWorks, flags
    }
}
