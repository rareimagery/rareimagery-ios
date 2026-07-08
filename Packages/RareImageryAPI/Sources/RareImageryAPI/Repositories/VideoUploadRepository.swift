import Foundation

public struct VideoUploadResponse: Codable, Sendable {
    public let videoId: String
    public let url: String
    /// Public playable URL — present only when the clip linked to a draft product.
    public let videoUrl: String?
}

/// Capture-clip upload (CAPTURE-CONTRACT.md §4). Multipart `POST /api/mobile/upload-video`.
/// Fired async so it never blocks the result screen. Passing `draftUuid` links the
/// clip to that draft product server-side, which stores it publicly and sets
/// field_video_url — the video the store detail page plays. Without a draftUuid it's
/// private retention only. The response's `videoUrl` is non-nil only when linked.
public actor VideoUploadRepository {
    private let client: APIClient
    private let logger = APILogger(category: "VideoUploadRepository")

    public init(client: APIClient) { self.client = client }

    public func upload(fileURL: URL, draftUuid: String? = nil) async throws -> VideoUploadResponse {
        let fileData = try Data(contentsOf: fileURL)
        let boundary = "Boundary-\(UUID().uuidString)"

        var body = Data()
        func appendString(_ string: String) { body.append(Data(string.utf8)) }
        if let draftUuid, !draftUuid.isEmpty {
            appendString("--\(boundary)\r\n")
            appendString("Content-Disposition: form-data; name=\"draftUuid\"\r\n\r\n")
            appendString("\(draftUuid)\r\n")
        }
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
