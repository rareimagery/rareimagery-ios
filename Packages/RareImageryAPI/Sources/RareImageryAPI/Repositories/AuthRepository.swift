import Foundation

public actor AuthRepository {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    private struct CallbackBody: Encodable {
        let code: String
        let codeVerifier: String
        let redirectUri: String

        enum CodingKeys: String, CodingKey {
            case code
            case codeVerifier = "code_verifier"
            case redirectUri = "redirect_uri"
        }
    }

    public func completeOAuth(code: String, codeVerifier: String, redirectURI: String) async throws -> AuthTokenResponse {
        let endpoint = try APIEndpoint.json(
            path: "/api/mobile/auth/x/callback",
            method: .post,
            body: CallbackBody(code: code, codeVerifier: codeVerifier, redirectUri: redirectURI),
            requiresAuth: false,
            timeout: 20
        )
        return try await client.send(endpoint)
    }

    public func refresh() async throws -> AuthTokenResponse {
        try await client.refreshTokens()
    }
}
