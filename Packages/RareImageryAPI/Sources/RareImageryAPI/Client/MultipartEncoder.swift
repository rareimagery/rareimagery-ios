import Foundation

/// RFC 7578 multipart/form-data encoder.
/// Single-file uploads only; sufficient for /api/upload.
public struct MultipartEncoder: Sendable {
    public let boundary: String

    public init(boundary: String? = nil) {
        self.boundary = boundary ?? "----RareImageryBoundary-\(UUID().uuidString)"
    }

    public var contentTypeHeader: String {
        "multipart/form-data; boundary=\(boundary)"
    }

    public func encode(
        file data: Data,
        fieldName: String = "file",
        filename: String = "photo.jpg",
        mimeType: String = "image/jpeg",
        additionalFields: [String: String] = [:]
    ) -> Data {
        var body = Data()
        let crlf = "\r\n"

        for (name, value) in additionalFields {
            body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\(crlf)\(crlf)".data(using: .utf8)!)
            body.append("\(value)\(crlf)".data(using: .utf8)!)
        }

        body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(filename)\"\(crlf)".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\(crlf)\(crlf)".data(using: .utf8)!)
        body.append(data)
        body.append("\(crlf)--\(boundary)--\(crlf)".data(using: .utf8)!)
        return body
    }
}
