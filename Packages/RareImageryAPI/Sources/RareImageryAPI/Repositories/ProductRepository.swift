import Foundation

public actor ProductRepository {
    private let client: APIClient
    private let logger = APILogger(category: "ProductRepository")

    public init(client: APIClient) {
        self.client = client
    }

    // MARK: - POST /api/vision/analyze  (resale-draft, JSON + base64 data URLs)
    //
    // Per BFF agent handoff 2026-05-22 the contract is JSON + base64 data URLs
    // with `heroOnly: true` (server analyzes the first image only).
    // CLAUDE.md's multipart/hero_index description is stale and will be updated.

    public enum AnalyzeIntent: String, Sendable {
        case resell
        case designMerch = "design_merch"

        init(from intent: ProductIntent) {
            switch intent {
            case .resell: self = .resell
            case .designMerch: self = .designMerch
            case .unknown: self = .resell  // default to resale for "not sure" until we wire merch-ideas
            }
        }
    }

    private struct AnalyzeRequest: Encodable {
        let imageUrls: [String]
        let productIntent: String
        let voiceTranscript: String?
        let heroOnly: Bool
        let source: String?   // "photo" | "video" — tags the analysis server-side
    }

    /// Calls `/api/vision/analyze`. `dataURLs` should be JPEG base64 data URLs:
    /// `data:image/jpeg;base64,<payload>`. Up to 4 entries. If `heroOnly` is true
    /// (default) the server only analyzes the first image.
    public func analyze(
        dataURLs: [String],
        intent: ProductIntent = .resell,
        voiceTranscript: String? = nil,
        heroOnly: Bool = true,
        source: String? = nil
    ) async throws -> VisionResult {
        guard !dataURLs.isEmpty else {
            throw APIError.badRequest(code: nil, message: "analyze called with zero images")
        }
        guard dataURLs.count <= 4 else {
            throw APIError.badRequest(code: nil, message: "analyze accepts at most 4 images, got \(dataURLs.count)")
        }

        let body = AnalyzeRequest(
            imageUrls: dataURLs,
            productIntent: AnalyzeIntent(from: intent).rawValue,
            voiceTranscript: voiceTranscript?.isEmpty == true ? nil : voiceTranscript,
            heroOnly: heroOnly,
            source: source
        )

        // Force camelCase keys — APIEndpoint.json would convert to snake_case
        // and the BFF expects camelCase on this route.
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys
        let data = try encoder.encode(body)

        let endpoint = APIEndpoint(
            path: "/api/vision/analyze",
            method: .post,
            body: data,
            requiresAuth: true,
            contentType: "application/json",
            timeout: 90  // BFF enforces 90s; allow the full budget for Grok→Claude cascade
        )
        logger.info("analyze: \(dataURLs.count) images, intent=\(intent.rawValue), heroOnly=\(heroOnly)")
        return try await client.send(endpoint)
    }

    // MARK: - POST /api/vision/merch-ideas  (merch-creation pipeline, JSON + base64)
    //
    // Distinct from `/api/vision/analyze` — returns 3–5 merch ideas with
    // a primary recommendation index. Per BFF agent handoff 2026-05-22.

    public func merchIdeas(
        dataURLs: [String],
        productIntent: MerchProductIntent = .designMerch,
        productType: MerchProductType? = nil,
        voiceTranscript: String? = nil,
        featureFriends: [String] = [],
        heroOnly: Bool = true
    ) async throws -> MerchIdeasResponse {
        guard !dataURLs.isEmpty else {
            throw APIError.badRequest(code: nil, message: "merchIdeas called with zero images")
        }
        guard dataURLs.count <= 4 else {
            throw APIError.badRequest(code: nil, message: "merchIdeas accepts at most 4 images, got \(dataURLs.count)")
        }
        guard featureFriends.count <= 24 else {
            throw APIError.badRequest(code: nil, message: "featureFriends capped at 24")
        }

        let body = MerchIdeasRequest(
            imageUrls: dataURLs,
            productIntent: productIntent,
            productType: productType,
            voiceTranscript: voiceTranscript?.isEmpty == true ? nil : voiceTranscript,
            featureFriends: featureFriends.isEmpty ? nil : featureFriends,
            heroOnly: heroOnly
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys  // BFF expects camelCase
        let data = try encoder.encode(body)

        let endpoint = APIEndpoint(
            path: "/api/vision/merch-ideas",
            method: .post,
            body: data,
            requiresAuth: true,
            contentType: "application/json",
            timeout: 90  // matches BFF maxDuration
        )
        logger.info("merch-ideas: \(dataURLs.count) images, friends=\(featureFriends.count), heroOnly=\(heroOnly)")
        return try await client.send(endpoint)
    }

    // MARK: - GET /api/products/[uuid]

    public func get(uuid: String) async throws -> ProductDetail {
        let endpoint = APIEndpoint(
            path: "/api/products/\(uuid)",
            method: .get
        )
        return try await client.send(endpoint)
    }

    // MARK: - PATCH /api/products/[uuid]

    public func patch(uuid: String, fields: ProductPatchRequest) async throws -> ProductDetail {
        let endpoint = try APIEndpoint.json(
            path: "/api/products/\(uuid)",
            method: .patch,
            body: fields
        )
        return try await client.send(endpoint)
    }

    // MARK: - DELETE /api/products/[uuid]

    public func delete(uuid: String) async throws {
        let endpoint = APIEndpoint(
            path: "/api/products/\(uuid)",
            method: .delete
        )
        _ = try await client.sendRaw(endpoint)
    }

    // MARK: - POST /api/products/[uuid]/publish

    public func publish(uuid: String) async throws -> ProductDetail {
        let endpoint = APIEndpoint(
            path: "/api/products/\(uuid)/publish",
            method: .post,
            body: nil,
            contentType: "application/json"
        )
        return try await client.send(endpoint)
    }
}
