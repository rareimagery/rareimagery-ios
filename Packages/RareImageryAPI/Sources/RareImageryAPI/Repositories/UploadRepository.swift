import Foundation

public actor UploadRepository {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func upload(
        jpegData: Data,
        filename: String = "photo.jpg"
    ) async throws -> UploadResponse {
        let encoder = MultipartEncoder()
        let body = encoder.encode(file: jpegData, filename: filename)
        let endpoint = APIEndpoint(
            path: "/api/upload",
            method: .post,
            body: body,
            requiresAuth: true,
            contentType: encoder.contentTypeHeader,
            timeout: 30
        )
        return try await client.send(endpoint)
    }
}
