import Foundation

/// RFC 7578 multipart/form-data encoder supporting any number of text + file parts.
public struct MultipartEncoder: Sendable {
    public let boundary: String

    public init(boundary: String? = nil) {
        self.boundary = boundary ?? "----RareImageryBoundary-\(UUID().uuidString)"
    }

    public var contentTypeHeader: String {
        "multipart/form-data; boundary=\(boundary)"
    }

    public struct Part: Sendable {
        public enum Body: Sendable {
            case text(String)
            case file(data: Data, filename: String, mimeType: String)
        }
        public let name: String
        public let body: Body

        public init(name: String, body: Body) {
            self.name = name
            self.body = body
        }

        public static func text(_ value: String, name: String) -> Part {
            Part(name: name, body: .text(value))
        }

        public static func file(
            _ data: Data,
            name: String,
            filename: String,
            mimeType: String = "image/jpeg"
        ) -> Part {
            Part(name: name, body: .file(data: data, filename: filename, mimeType: mimeType))
        }
    }

    public func encode(parts: [Part]) -> Data {
        var body = Data()
        let crlf = "\r\n"
        for part in parts {
            body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
            switch part.body {
            case .text(let value):
                body.append("Content-Disposition: form-data; name=\"\(part.name)\"\(crlf)\(crlf)".data(using: .utf8)!)
                body.append("\(value)\(crlf)".data(using: .utf8)!)
            case .file(let data, let filename, let mimeType):
                body.append("Content-Disposition: form-data; name=\"\(part.name)\"; filename=\"\(filename)\"\(crlf)".data(using: .utf8)!)
                body.append("Content-Type: \(mimeType)\(crlf)\(crlf)".data(using: .utf8)!)
                body.append(data)
                body.append(crlf.data(using: .utf8)!)
            }
        }
        body.append("--\(boundary)--\(crlf)".data(using: .utf8)!)
        return body
    }
}
