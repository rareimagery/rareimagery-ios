import Foundation

/// Minimal JSON:API document helpers for Drupal entity reads.
public struct JSONAPIDocument<Attr: Decodable & Sendable>: Decodable, Sendable {
    public let data: [JSONAPIResource<Attr>]
    public let included: [RawResource]?

    public init(data: [JSONAPIResource<Attr>], included: [RawResource]? = nil) {
        self.data = data
        self.included = included
    }
}

public struct JSONAPISingleDocument<Attr: Decodable & Sendable>: Decodable, Sendable {
    public let data: JSONAPIResource<Attr>

    public init(data: JSONAPIResource<Attr>) {
        self.data = data
    }
}

public struct JSONAPIResource<Attr: Decodable & Sendable>: Decodable, Sendable {
    public let id: String
    public let type: String
    public let attributes: Attr

    public init(id: String, type: String, attributes: Attr) {
        self.id = id
        self.type = type
        self.attributes = attributes
    }
}

/// Untyped included resources (media, files) — resolved by id when needed.
public struct RawResource: Decodable, Sendable {
    public let id: String
    public let type: String
    public let attributes: [String: AnyDecodable]?

    public init(id: String, type: String, attributes: [String: AnyDecodable]?) {
        self.id = id
        self.type = type
        self.attributes = attributes
    }
}

public struct AnyDecodable: Decodable, @unchecked Sendable {
    public let value: Any

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let v = try? container.decode(Bool.self) {
            value = v
        } else if let v = try? container.decode(Int.self) {
            value = v
        } else if let v = try? container.decode(Double.self) {
            value = v
        } else if let v = try? container.decode(String.self) {
            value = v
        } else if let v = try? container.decode([String: AnyDecodable].self) {
            value = v.mapValues(\.value)
        } else if let v = try? container.decode([AnyDecodable].self) {
            value = v.map(\.value)
        } else {
            value = NSNull()
        }
    }
}
