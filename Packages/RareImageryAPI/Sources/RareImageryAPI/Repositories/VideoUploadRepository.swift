import Foundation

public struct VideoUploadResponse: Codable, Sendable {
    public let videoId: String
    public let url: String
}

/// Raw-clip retention (CAPTURE-CONTRACT.md §4). Multipart `POST /api/mobile/upload-video`.
/// The endpoint is **backend-owned and not live yet** — callers gate this behind
/// `AppState.useMocks` and fire it async so it never blocks the result screen.
public actor VideoUploadRepository {
    private let client: APIClient
    private let logger = APILogger(category: "VideoUploadRepository")

    public init(client: APIClient) { self.client = client }

    public func upload(fileURL: URL) async throws -> VideoUploadResponse {
        let fileData = try Data(contentsOf: fileURL)
        let boundary = "Boundary-\(UUID().uuidString)"

        var body = Data()
        func appendString(_ string: String) { body.append(Data(string.utf8)) }
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"file\"; filename=\"clip.mov\"\r\n")
        appendString("Content-Type: video/quicktime\r\n\r\n")
        body.append(fileData)
        appendString("\r\n--\(boundary)--\r\n")

        let endpoint = APIEndpoint(
            path: "/api/mobile/upload-video",
            method: .post,
            body: body,
            requiresAuth: true,
            contentType: "multipart/form-data; boundary=\(boundary)",
            timeout: 120
        )
        logger.info("upload-video: \(fileData.count) bytes")
        return try await client.send(endpoint)
    }
}
