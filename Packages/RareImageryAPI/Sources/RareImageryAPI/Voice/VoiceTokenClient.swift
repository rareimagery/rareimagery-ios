import Foundation

/// Mints an ephemeral xAI Realtime token via Drupal
/// `POST /api/v1/realtime-token`. The app never holds a durable xAI key.
public actor VoiceTokenClient {
    private let client: APIClient
    private let logger = APILogger(category: "VoiceToken")

    public init(client: APIClient) {
        self.client = client
    }

    public func mint() async throws -> RealtimeToken {
        let url = await client.endpoints.apiV1.appending(path: "realtime-token")
        logger.info("mint realtime-token")
        let env: DataEnvelope<RealtimeToken> = try await client.request(
            DataEnvelope<RealtimeToken>.self,
            url: url,
            method: "POST",
            body: Data("{}".utf8),
            contentType: "application/json",
            accept: "application/json",
            authenticated: true
        )
        return env.data
    }
}
