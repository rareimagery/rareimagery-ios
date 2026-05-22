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
}
