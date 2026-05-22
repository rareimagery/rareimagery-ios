import Foundation

public actor ProductRepository {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func fromImages(
        heroURL: URL,
        additionalURLs: [URL] = [],
        voiceTranscript: String? = nil,
        intent: ProductIntent = .unknown,
        storeUuid: String? = nil
    ) async throws -> ProductDraft {
        let body = ProductFromImagesRequest(
            heroUrl: heroURL.absoluteString,
            additionalUrls: additionalURLs.map(\.absoluteString),
            voiceTranscript: voiceTranscript,
            intent: intent,
            storeUuid: storeUuid
        )
        let endpoint = try APIEndpoint.json(
            path: "/api/products/from-images",
            method: .post,
            body: body,
            timeout: 30
        )
        return try await client.send(endpoint)
    }
}
