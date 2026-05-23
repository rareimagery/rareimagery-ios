import Foundation

/// Body for `PATCH /api/products/[uuid]`. Only set the fields you want to change.
public struct ProductPatchRequest: Encodable, Sendable {
    public let title: String?
    public let description: String?
    public let price: Decimal?
    public let category: ProductCategory?
    public let condition: ProductCondition?
    public let tags: [String]?

    public init(
        title: String? = nil,
        description: String? = nil,
        price: Decimal? = nil,
        category: ProductCategory? = nil,
        condition: ProductCondition? = nil,
        tags: [String]? = nil
    ) {
        self.title = title
        self.description = description
        self.price = price
        self.category = category
        self.condition = condition
        self.tags = tags
    }
}
