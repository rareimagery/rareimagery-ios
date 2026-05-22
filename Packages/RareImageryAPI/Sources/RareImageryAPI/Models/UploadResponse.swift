import Foundation

public struct UploadResponse: Codable, Sendable, Equatable {
    public let url: String
    public let size: Int?
    public let contentType: String?

    enum CodingKeys: String, CodingKey {
        case url
        case size
        case contentType = "content_type"
    }

    public var publicURL: URL? { URL(string: url) }
}
