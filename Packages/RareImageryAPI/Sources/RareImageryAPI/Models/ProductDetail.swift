import Foundation

/// Returned by `GET /api/products/[uuid]` and the CRUD variants.
/// Field names lean permissive so the client doesn't break when the BFF adds keys.
public struct ProductDetail: Codable, Sendable, Equatable, Identifiable {
    public let uuid: String
    public let title: String?
    public let description: String?
    public let price: Decimal?
    public let status: String?
    public let thumbnail: String?
    public let storefrontUrl: String?
    public let category: ProductCategory?
    public let condition: ProductCondition?
    public let tags: [String]?
    public let createdAt: String?
    public let updatedAt: String?

    public var id: String { uuid }
    public var isPublished: Bool { status == "published" }
}
