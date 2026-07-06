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
        let heroIndex: Int?
        let mode: String?
        /// "photo" | "video" — the BFF's Zod schema reads `captureSource`
        /// (VisionAnalyzeSchema); a `source` key is silently stripped and
        /// the server defaults to "photo".
        let captureSource: String?
    }

    /// Calls `/api/vision/analyze`. `dataURLs` should be JPEG base64 data URLs:
    /// `data:image/jpeg;base64,<payload>`. Up to 4 entries. If `heroOnly` is true
    /// (default) the server only analyzes the first image.
    public func analyze(
        dataURLs: [String],
        intent: ProductIntent = .resell,
        voiceTranscript: String? = nil,
        heroOnly: Bool = true,
        heroIndex: Int? = nil,
        mode: VisionAnalyzeMode = .product,
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
            heroIndex: heroIndex,
            mode: mode.rawValue,
            captureSource: source
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
        logger.info("analyze: \(dataURLs.count) images, intent=\(intent.rawValue), mode=\(mode.rawValue), heroOnly=\(heroOnly)")
        return try await client.send(endpoint)
    }

    // MARK: - POST /api/v1/vision/value  (anonymous pre-login valuation)
    //
    // Value-first funnel contract (postdates VALUE-FIRST-OAUTH.md's
    // draft_token-only description — this is the current source of truth):
    // no Authorization header, identity is `deviceId` alone. Reuses the
    // shared `ProductDraft` shape via `AnonymousValueResponse` — this is
    // NOT a parallel model, just a different auth mode on vision analysis.
    // Success returns `draftUuid` (a Drupal product uuid, or nil) which the
    // caller should persist and thread through the X OAuth claim callback.

    /// Calls `/api/v1/vision/value`. `dataURLs` should be JPEG base64 data
    /// URLs (1-4 entries).
    ///
    /// `authenticated` toggles the bearer token. The anonymous funnel calls
    /// with `false` (pre-session valuation). In-app product creation (a
    /// signed-in creator) calls with `true`: the BFF then binds the created
    /// draft to the creator immediately, so it lands as an editable product
    /// in their store (response `owned == true`). Same endpoint, two modes —
    /// the server distinguishes by the token's audience.
    public func valueAnonymously(
        dataURLs: [String],
        voiceTranscript: String? = nil,
        deviceId: String,
        source: String? = nil,
        authenticated: Bool = false
    ) async throws -> AnonymousValueResponse {
        guard !dataURLs.isEmpty else {
            throw APIError.badRequest(code: nil, message: "valueAnonymously called with zero images")
        }
        guard dataURLs.count <= 4 else {
            throw APIError.badRequest(code: nil, message: "valueAnonymously accepts at most 4 images, got \(dataURLs.count)")
        }

        let body = AnonymousValueRequest(
            imageUrls: dataURLs,
            voiceTranscript: voiceTranscript?.isEmpty == true ? nil : voiceTranscript,
            deviceId: deviceId,
            source: source
        )

        // Force camelCase keys, matching the rest of the vision surface
        // (APIEndpoint.json would convert to snake_case).
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys
        let data = try encoder.encode(body)

        let endpoint = APIEndpoint(
            path: "/api/v1/vision/value",
            method: .post,
            body: data,
            requiresAuth: authenticated,
            contentType: "application/json",
            timeout: 90
        )
        logger.info("valueAnonymously: \(dataURLs.count) images, deviceId=\(deviceId), authed=\(authenticated)")
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

    // MARK: - GET /api/stores/products  (the signed-in creator's products)

    /// Lists every product owned by the signed-in creator (drafts + live),
    /// filtered server-side by their profile — never trusts client input.
    public func listMine() async throws -> [StoreProduct] {
        let endpoint = APIEndpoint(
            path: "/api/stores/products",
            method: .get,
            requiresAuth: true,
            timeout: 20
        )
        let response: StoreProductsResponse = try await client.send(endpoint)
        return response.products
    }

    // MARK: - GET /api/stores/edit  (the signed-in creator's public profile)

    /// Loads the creator's storefront profile — X avatar, banner, display
    /// name, bio, slug — for the Page tab's public-page preview.
    public func myProfile() async throws -> StoreProfile {
        let endpoint = APIEndpoint(
            path: "/api/stores/edit",
            method: .get,
            requiresAuth: true,
            timeout: 20
        )
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
        // PATCH returns an ack ({ ok, updated_fields, saved_at }), not a
        // ProductDetail — decoding it as one used to throw and surface as
        // "price isn't set" even though the save succeeded. Ack it raw, then
        // re-read the product for fresh detail.
        _ = try await client.sendRaw(endpoint)
        return try await get(uuid: uuid)
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
            requiresAuth: true,
            contentType: "application/json"
        )
        // Publish returns an ack ({ ok, product_uuid, status, storefront_url }),
        // not a ProductDetail — decoding it as one threw on the missing `uuid`
        // and surfaced as "Couldn't publish" despite the server returning 200.
        // Ack it raw, then re-read the (now published) product.
        _ = try await client.sendRaw(endpoint)
        return try await get(uuid: uuid)
    }
}
