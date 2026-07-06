import Foundation

/// Wraps POST /api/v1/circle/share on the Next.js BFF.
///
/// BFF contract (defined in x-store-next/src/app/api/v1/circle/share/route.ts):
///   200 — at least one recipient succeeded (check `failed > 0` for partial)
///   400 — INVALID_JSON or VALIDATION_FAILED
///   401 — auth missing or invalid
///   502 — every recipient failed (returned as throw, mapped by APIClient)
///   500 — internal error in the fanout loop
///
/// The repository never throws on partial success — that's a meaningful
/// outcome the sheet renders as F3. Only true transport / auth / server
/// errors bubble up.
public actor CircleShareRepository {
    private let client: APIClient
    private let logger = APILogger(category: "CircleShareRepository")

    public init(client: APIClient) {
        self.client = client
    }

    /// Fan out a draft to N circle recipients. Returns the BFF's per-recipient
    /// result array so the caller can render partial-success UI.
    ///
    /// Throws on transport / auth / 5xx errors. A 502 (all failed) IS a
    /// throw — the sheet treats it as F2 (full failure) rather than F3
    /// (partial). Use `error` in the catch site to distinguish.
    public func send(_ request: CircleShareRequest) async throws -> CircleShareResponse {
        let data = try JSONEncoder().encode(request)
        let endpoint = APIEndpoint(
            path: "/api/v1/circle/share",
            method: .post,
            body: data,
            requiresAuth: true,
            contentType: "application/json",
            timeout: 20
        )
        return try await client.send(endpoint, as: CircleShareResponse.self)
    }
}
