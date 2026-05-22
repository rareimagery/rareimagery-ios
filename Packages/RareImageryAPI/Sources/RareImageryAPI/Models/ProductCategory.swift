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
}
