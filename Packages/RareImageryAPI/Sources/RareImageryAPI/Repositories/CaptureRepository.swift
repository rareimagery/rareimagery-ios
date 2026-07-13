import Foundation

struct AnalyzeCaptureRequest: Encodable, Sendable {
    let mediaIds: [Int]
    let transcript: String

    enum CodingKeys: String, CodingKey {
        case mediaIds = "media_ids"
        case transcript
    }
}

struct CreateListingRequest: Encodable, Sendable {
    let title: String
    let description: String
    let price: String
    let currency: String
    let status: String
    let analysis: AnalysisResult?
    let mediaIds: [Int]

    enum CodingKeys: String, CodingKey {
        case title, description, price, currency, status, analysis
        case mediaIds = "media_ids"
    }
}

/// Typed wrappers for rareimagery_api capture endpoints
/// (`/api/v1/analyze-capture`, `/api/v1/listings`).
///
/// Depends on Drupal Tasks 3–5. As of 2026-07-13 these routes are not yet
/// public on rareimagery.net (module not enabled) — clients will see
/// `.notFound` until the module ships.
public actor CaptureRepository {
    private let client: APIClient
    private let logger = APILogger(category: "CaptureRepository")

    public init(client: APIClient) {
        self.client = client
    }

    public func analyze(mediaIDs: [Int], transcript: String) async throws -> AnalysisResult {
        guard !mediaIDs.isEmpty else {
            throw APIError.badRequest(code: nil, message: "analyze requires at least one media_id")
        }
        let body = try JSONEncoder().encode(
            AnalyzeCaptureRequest(mediaIds: mediaIDs, transcript: transcript)
        )
        let url = await client.endpoints.apiV1.appending(path: "analyze-capture")
        logger.info("analyze-capture: \(mediaIDs.count) media, transcript=\(transcript.count) chars")
        let env: DataEnvelope<AnalysisResult> = try await client.request(
            DataEnvelope<AnalysisResult>.self,
            url: url,
            method: "POST",
            body: body,
            contentType: "application/json",
            accept: "application/json",
            authenticated: true
        )
        return env.data
    }

    public func createListing(
        title: String,
        description: String,
        price: String,
        status: String = "draft",
        currency: String = "USD",
        analysis: AnalysisResult?,
        mediaIDs: [Int]
    ) async throws -> ListingResult {
        let body = try JSONEncoder().encode(
            CreateListingRequest(
                title: title,
                description: description,
                price: price,
                currency: currency,
                status: status,
                analysis: analysis,
                mediaIds: mediaIDs
            )
        )
        let url = await client.endpoints.apiV1.appending(path: "listings")
        logger.info("listings: status=\(status), media=\(mediaIDs.count)")
        let env: DataEnvelope<ListingResult> = try await client.request(
            DataEnvelope<ListingResult>.self,
            url: url,
            method: "POST",
            body: body,
            contentType: "application/json",
            accept: "application/json",
            authenticated: true
        )
        return env.data
    }
}
