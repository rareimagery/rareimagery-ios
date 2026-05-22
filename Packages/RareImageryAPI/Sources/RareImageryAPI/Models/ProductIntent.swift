import Foundation

public enum ProductIntent: String, Codable, Sendable, CaseIterable {
    case resell
    case designMerch = "design_merch"
    case unknown

    public var displayName: String {
        switch self {
        case .resell: return "Resell as-is"
        case .designMerch: return "Design merch"
        case .unknown: return "Not sure yet"
        }
    }
}
