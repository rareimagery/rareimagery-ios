import Foundation

/// A product in the signed-in creator's store, as returned by
/// `GET /api/stores/products` (`products[]`). Distinct from `ProductDetail`
/// (single-product read) — this is the list-row shape, tolerant of the
/// gallery endpoint's snake_case + string-typed price.
public struct StoreProduct: Codable, Sendable, Equatable, Identifiable {
    public let id: String            // product uuid
    public let title: String?
    public let description: String?
    public let price: String?        // "12.00" (string from Drupal)
    public let currency: String?
    public let imageUrl: String?
    public let productType: String?
    /// Drupal commerce_product status: 1 = published, 0 = unpublished draft.
    public let status: Int?

    public var isPublished: Bool { status == 1 }

    public var priceDisplay: String? {
        guard let price, let value = Decimal(string: price) else { return nil }
        return "$\(value as NSDecimalNumber)"
    }

    // Plain camelCase keys: APIClient decodes with .convertFromSnakeCase,
    // so image_url/product_type are already imageUrl/productType by the time
    // this container is keyed — snake_case rawValues here would double-convert.
    enum CodingKeys: String, CodingKey {
        case id, title, description, price, currency, imageUrl, productType, status
    }

    // Status arrives as an int (1/0) or occasionally a bool/string across
    // Drupal versions — decode leniently so the whole list never fails.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        price = try c.decodeIfPresent(String.self, forKey: .price)
        currency = try c.decodeIfPresent(String.self, forKey: .currency)
        imageUrl = try c.decodeIfPresent(String.self, forKey: .imageUrl)
        productType = try c.decodeIfPresent(String.self, forKey: .productType)
        if let i = (try? c.decodeIfPresent(Int.self, forKey: .status)) ?? nil {
            status = i
        } else if let b = (try? c.decodeIfPresent(Bool.self, forKey: .status)) ?? nil {
            status = b ? 1 : 0
        } else if let s = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? nil {
            status = (s == "1" || s.lowercased() == "published") ? 1 : 0
        } else {
            status = nil
        }
    }
}

public struct StoreProductsResponse: Decodable, Sendable {
    public let products: [StoreProduct]
}
