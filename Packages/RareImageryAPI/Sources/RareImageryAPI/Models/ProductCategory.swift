import Foundation

public enum ProductCategory: String, Codable, Sendable, CaseIterable {
    case apparel
    case footwear
    case accessories
    case art
    case home
    case electronics
    case books
    case media
    case sports
    case toys
    case collectibles
    case other

    public var displayName: String {
        switch self {
        case .apparel: return "Apparel"
        case .footwear: return "Footwear"
        case .accessories: return "Accessories"
        case .art: return "Art"
        case .home: return "Home & Living"
        case .electronics: return "Electronics"
        case .books: return "Books"
        case .media: return "Media"
        case .sports: return "Sports"
        case .toys: return "Toys"
        case .collectibles: return "Collectibles"
        case .other: return "Other"
        }
    }

    /// Tolerant decode: Grok's drafts arrive with display-style strings
    /// ("Other", "Art & Prints", "Home & Living") rather than contract raw
    /// values. Swift throws `dataCorrupted` on unknown enum raw values even
    /// for optional properties, which silently killed real valuations in the
    /// funnel (showed the mock instead). Normalize + alias-map, and fall back
    /// to `.other` — never throw.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ProductCategory.lenient(raw)
    }

    public static func lenient(_ raw: String) -> ProductCategory {
        let key = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = ProductCategory(rawValue: key) { return exact }
        switch key {
        case let k where k.contains("art") || k.contains("print"): return .art
        case let k where k.contains("apparel") || k.contains("cloth") || k.contains("fashion"): return .apparel
        case let k where k.contains("shoe") || k.contains("sneaker") || k.contains("footwear"): return .footwear
        case let k where k.contains("accessor") || k.contains("jewel") || k.contains("bag") || k.contains("watch"): return .accessories
        case let k where k.contains("home") || k.contains("living") || k.contains("furnit") || k.contains("decor") || k.contains("kitchen"): return .home
        case let k where k.contains("electronic") || k.contains("camera") || k.contains("audio") || k.contains("tech") || k.contains("comput") || k.contains("phone"): return .electronics
        case let k where k.contains("book"): return .books
        case let k where k.contains("media") || k.contains("vinyl") || k.contains("record") || k.contains("music") || k.contains("movie") || k.contains("game"): return .media
        case let k where k.contains("sport") || k.contains("outdoor") || k.contains("fitness"): return .sports
        case let k where k.contains("toy") || k.contains("plush") || k.contains("figure"): return .toys
        case let k where k.contains("collect") || k.contains("antique") || k.contains("vintage") || k.contains("memorabilia") || k.contains("card"): return .collectibles
        default: return .other
        }
    }
}
