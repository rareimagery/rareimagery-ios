import Foundation

public actor AuthRepository {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    /// Per CLAUDE.md §2.2 the BFF expects camelCase keys here — EXCEPT the
    /// legacy draft-claim field, which the callback route reads as
    /// `draft_token` (x/callback/route.ts parses `body.draft_token`). Mixed
    /// casing there is the server's contract, not a client bug.
    ///
    /// `draftUuid` and `deviceId` are newer, additive, camelCase optional
    /// fields (current contract — postdates VALUE-FIRST-OAUTH.md's
    /// draft_token-only description). They ride alongside `draft_token`
    /// rather than replacing it: `draftUuid` is the Drupal product uuid from
    /// the anonymous `/api/v1/vision/value` response (when the user claims
    /// that specific draft), `deviceId` is the stable per-install id from
    /// `KeychainStore.stableDeviceId()`. Both default to nil so existing
    /// authenticated sign-in (no pending draft) is unaffected.
    private struct CallbackBody: Encodable {
        let code: String
        let codeVerifier: String
        let redirectUri: String
        let state: String?
        let draftToken: String?
        let draftUuid: String?
        let deviceId: String?

        enum CodingKeys: String, CodingKey {
            case code, codeVerifier, redirectUri, state
            case draftToken = "draft_token"
            case draftUuid, deviceId
        }
    }

    public func completeOAuth(
        code: String,
        codeVerifier: String,
        redirectURI: String,
        state: String? = nil,
        draftToken: String? = nil,
        draftUuid: String? = nil,
        deviceId: String? = nil
    ) async throws -> AuthTokenResponse {
        // Build the request manually so JSONEncoder doesn't apply
        // the client's default snake_case key strategy.
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys
        let body = try encoder.encode(
            CallbackBody(
                code: code,
                codeVerifier: codeVerifier,
                redirectUri: redirectURI,
                state: state,
                draftToken: draftToken,
                draftUuid: draftUuid,
                deviceId: deviceId
            )
        )
        let endpoint = APIEndpoint(
            path: "/api/mobile/auth/x/callback",
            method: .post,
            body: body,
            requiresAuth: false,
            contentType: "application/json",
            timeout: 20
        )
        return try await client.send(endpoint)
    }

    public func refresh() async throws -> AuthTokenResponse {
        try await client.refreshTokens()
    }
}
