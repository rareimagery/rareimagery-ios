import Foundation

public enum ProductCondition: String, Codable, Sendable, CaseIterable {
    case new
    case likeNew = "like_new"
    case lightlyWorn = "lightly_worn"
    case worn
    case forParts = "for_parts"
    case unknown

    public var displayName: String {
        switch self {
        case .new: return "New"
        case .likeNew: return "Like New"
        case .lightlyWorn: return "Lightly Worn"
        case .worn: return "Worn"
        case .forParts: return "For Parts"
        case .unknown: return "Unknown"
        }
    }

    /// Tolerant decode — same rationale as `ProductCategory.init(from:)`:
    /// Grok emits grading words outside the contract set ("good", "fair",
    /// "poor", "excellent", "mint"). Map them; never throw.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ProductCondition.lenient(raw)
    }

    public static func lenient(_ raw: String) -> ProductCondition {
        let key = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "-", with: "_")
        if let exact = ProductCondition(rawValue: key) { return exact }
        switch key {
        case "mint", "sealed", "new_in_box", "nib", "brand_new", "unworn", "unused": return .new
        case "excellent", "near_mint", "like_new_condition", "barely_used": return .likeNew
        case "good", "fair", "very_good", "gently_used", "used", "lightly_used", "pre_owned", "preowned": return .lightlyWorn
        case "poor", "heavily_worn", "well_worn", "damaged", "distressed", "acceptable": return .worn
        case "broken", "not_working", "parts_only", "for_repair", "as_is": return .forParts
        default: return .unknown
        }
    }
}
