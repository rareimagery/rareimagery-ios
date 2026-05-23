import Foundation

public actor AuthRepository {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    /// Per CLAUDE.md §2.2 the BFF expects camelCase keys here, not snake_case.
    private struct CallbackBody: Encodable {
        let code: String
        let codeVerifier: String
        let redirectUri: String
        let state: String?
    }

    public func completeOAuth(
        code: String,
        codeVerifier: String,
        redirectURI: String,
        state: String? = nil
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
                state: state
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
