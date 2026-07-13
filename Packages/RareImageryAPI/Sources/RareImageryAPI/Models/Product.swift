import Foundation

/// Attributes on `commerce_product--*` JSON:API resources.
///
/// Verified 2026-07-13 against live
/// `GET /jsonapi/commerce_product/physical?page[limit]=1` and `/default`:
/// `title`, `status` (bool), `created` (ISO-8601), `body.value`.
/// Extra fields (`drupal_internal__product_id`, `path`, custom fields) are ignored.
public struct ProductAttributes: Decodable, Sendable, Hashable {
    public let title: String
    public let status: Bool
    public let created: Date

    public struct Body: Decodable, Sendable, Hashable {
        public let value: String?

        public init(value: String?) {
            self.value = value
        }
    }

    public let body: Body?

    public init(title: String, status: Bool, created: Date, body: Body?) {
        self.title = title
        self.status = status
        self.created = created
        self.body = body
    }

    enum CodingKeys: String, CodingKey {
        case title, status, created, body
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        created = try container.decode(Date.self, forKey: .created)
        body = try container.decodeIfPresent(Body.self, forKey: .body)

        if let boolStatus = try? container.decode(Bool.self, forKey: .status) {
            status = boolStatus
        } else if let intStatus = try? container.decode(Int.self, forKey: .status) {
            status = intStatus != 0
        } else if let stringStatus = try? container.decode(String.self, forKey: .status) {
            status = stringStatus == "1" || stringStatus.lowercased() == "true"
        } else {
            status = false
        }
    }
}

/// App-facing product row from JSON:API (capture bundle).
public struct Product: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let isLive: Bool
    public let descriptionText: String
    public let created: Date

    public init(resource: JSONAPIResource<ProductAttributes>) {
        id = resource.id
        title = resource.attributes.title
        isLive = resource.attributes.status
        descriptionText = resource.attributes.body?.value ?? ""
        created = resource.attributes.created
    }

    public init(id: String, title: String, isLive: Bool, descriptionText: String, created: Date) {
        self.id = id
        self.title = title
        self.isLive = isLive
        self.descriptionText = descriptionText
        self.created = created
    }
}
