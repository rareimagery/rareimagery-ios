import Foundation

/// File entity returned by Drupal JSON:API binary field upload
/// (`POST /jsonapi/media/{bundle}/{field}`).
struct JSONAPIFileAttributes: Decodable, Sendable {
    let filename: String?
    let filemime: String?
    let filesize: Int?
    let drupalInternalFid: Int?

    enum CodingKeys: String, CodingKey {
        case filename, filemime, filesize
        case drupalInternalFid = "drupal_internal__fid"
    }
}

/// Media entity attributes — `drupal_internal__mid` is what `/api/v1/listings` wants.
struct JSONAPIMediaAttributes: Decodable, Sendable {
    let name: String?
    let status: Bool?
    let drupalInternalMid: Int

    enum CodingKeys: String, CodingKey {
        case name, status
        case drupalInternalMid = "drupal_internal__mid"
    }
}

struct JSONAPIMediaCreateBody: Encodable, Sendable {
    struct DataObject: Encodable, Sendable {
        let type: String
        let attributes: Attributes
        let relationships: [String: Relationship]

        struct Attributes: Encodable, Sendable {
            let name: String
        }

        struct Relationship: Encodable, Sendable {
            let data: ResourceIdentifier
        }

        struct ResourceIdentifier: Encodable, Sendable {
            let type: String
            let id: String
            let meta: Meta?

            struct Meta: Encodable, Sendable {
                let alt: String?
            }

            init(type: String, id: String, alt: String? = nil) {
                self.type = type
                self.id = id
                self.meta = alt.map { Meta(alt: $0) }
            }
        }
    }

    let data: DataObject
}
