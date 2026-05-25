import Foundation

/// Wraps POST /api/mobile/auth/anonymous — the Phase 3 trial-mode
/// bootstrap endpoint.
///
/// Called from `AppState.bootstrap` on app launch when no production
/// `refreshToken` exists. The returned access token goes into the
/// regular `.accessToken` Keychain slot so APIClient's existing auth
/// header injection works unchanged — the discriminator between
/// production and anonymous sessions lives on `AuthSession.Status`,
/// not on which keychain key holds the token.
///
/// Auth: this endpoint requires NONE — it IS the bootstrap. The BFF
/// rate-limits the mint operation per IP (10/hr) to prevent token-
/// farming abuse.
public actor AnonymousAuthRepository {
    private let client: APIClient
    private let logger = APILogger(category: "AnonymousAuthRepository")

    public init(client: APIClient) {
        self.client = client
    }

    /// Mint a new anonymous JWT for the given device identity.
    /// Throws `APIError.rateLimited` on 429, `APIError.badRequest` on 400
    /// (malformed UUID), `APIError.serverError` on 500.
    public func requestToken(deviceId: String) async throws -> AnonymousAuthResponse {
        let payload = AnonymousAuthRequest(deviceId: deviceId)
        let body = try JSONEncoder().encode(payload)
        let endpoint = APIEndpoint(
            path: "/api/mobile/auth/anonymous",
            method: .post,
            body: body,
            requiresAuth: false,   // bootstrap — no token yet
            contentType: "application/json",
            timeout: 15
        )
        return try await client.send(endpoint, as: AnonymousAuthResponse.self)
    }
}
