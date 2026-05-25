import Foundation

/// Wraps POST /api/v1/design-studio/publish — the Phase 4.4 endpoint
/// that finally makes OnePageCreator's "Create + Launch" do something
/// real (creates a commerce_product/printful in Drupal linked to the
/// creator's storefront).
///
/// BFF contract:
///   200 — product created + IDs returned
///   400 — VALIDATION_FAILED (bad image_url shape, price ≤ 0, etc)
///   401 — auth required (anonymous trial users cannot publish)
///   403 — NO_PROFILE_UUID (mobile required for publish in v1)
///   404 — CREATOR_NOT_FOUND or NO_STORE (call provision-store first)
///   413 — IMAGE_TOO_LARGE (>8 MB image bytes)
///   422 — UNSUPPORTED_PRODUCT_KIND
///   500/502 — server / Drupal errors
///
/// The route requires X auth — anonymous trial users hit a hard wall
/// at OnePageCreator's Create+Launch button before reaching here. If
/// they somehow do (e.g. expired JWT mid-flow), the 401/403 is the
/// safety net.
public actor PublishProductRepository {
    private let client: APIClient
    private let logger = APILogger(category: "PublishProductRepository")

    public init(client: APIClient) {
        self.client = client
    }

    /// Publish a generated design as a commerce_product. Returns the
    /// new product's IDs so the UI can route to it or share its URL.
    public func publish(_ request: PublishProductRequest) async throws -> PublishProductResponse {
        let body = try JSONEncoder().encode(request)
        let endpoint = APIEndpoint(
            path: "/api/v1/design-studio/publish",
            method: .post,
            body: body,
            requiresAuth: true,
            contentType: "application/json",
            // Long enough for Drupal commerce_product save + image File
            // entity creation when image_url is a data: URL (~1 MB
            // base64 round-trip).
            timeout: 60
        )
        return try await client.send(endpoint, as: PublishProductResponse.self)
    }
}
