import Foundation

public actor AuthRepository {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    /// Per CLAUDE.md §2.2 the BFF expects camelCase keys here — EXCEPT the
    /// draft-claim field, which the callback route reads as `draft_token`
    /// (x/callback/route.ts parses `body.draft_token`). Mixed casing is the
    /// server's contract, not a client bug.
    private struct CallbackBody: Encodable {
        let code: String
        let codeVerifier: String
        let redirectUri: String
        let state: String?
        let draftToken: String?

        enum CodingKeys: String, CodingKey {
            case code, codeVerifier, redirectUri, state
            case draftToken = "draft_token"
        }
    }

    public func completeOAuth(
        code: String,
        codeVerifier: String,
        redirectURI: String,
        state: String? = nil,
        draftToken: String? = nil
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
                draftToken: draftToken
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
