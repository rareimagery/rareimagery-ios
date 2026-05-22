import Foundation

/// Coordinates the X OAuth 2.0 PKCE flow.
/// Mobile responsibility: generate verifier/challenge, build authorize URL, hold verifier in memory until the
/// callback returns the auth code, then exchange the code via AuthRepository (server completes with X).
public actor AuthService {
    private let configuration: APIConfiguration
    private let repository: AuthRepository
    private let client: APIClient
    private let logger = APILogger(category: "AuthService")

    private var pendingVerifier: String?
    private var pendingState: String?

    public init(configuration: APIConfiguration, repository: AuthRepository, client: APIClient) {
        self.configuration = configuration
        self.repository = repository
        self.client = client
    }

    public struct OAuthRequest: Sendable {
        public let authorizationURL: URL
        public let callbackScheme: String
    }

    /// Returns the URL to open in ASWebAuthenticationSession plus the callback scheme to listen for.
    public func startXAuth(scopes: [String] = ["tweet.read", "users.read", "offline.access"]) throws -> OAuthRequest {
        guard !configuration.xClientID.isEmpty else {
            throw APIError.invalidConfiguration("XClientID is empty — set XClientID in xcconfig / Info.plist")
        }
        let verifier = PKCE.generateVerifier()
        let challenge = PKCE.challenge(for: verifier)
        let state = PKCE.generateVerifier(length: 43)

        pendingVerifier = verifier
        pendingState = state

        var components = URLComponents(string: "https://x.com/i/oauth2/authorize")
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: configuration.xClientID),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]

        guard let url = components?.url else {
            throw APIError.invalidConfiguration("Could not construct X authorize URL")
        }

        logger.info("Built X authorize URL — redirect_uri=\(configuration.redirectURI)")
        return OAuthRequest(authorizationURL: url, callbackScheme: configuration.xCallbackScheme)
    }

    /// Process the callback URL returned by ASWebAuthenticationSession.
    /// Extracts the code, validates state, and exchanges via AuthRepository.
    public func completeXAuth(callbackURL: URL) async throws -> AuthTokenResponse {
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw APIError.authFailed("Malformed callback URL")
        }
        let items = components.queryItems ?? []
        if let err = items.first(where: { $0.name == "error" })?.value {
            throw APIError.authFailed("X returned error: \(err)")
        }
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw APIError.authFailed("No authorization code in callback")
        }
        if let state = items.first(where: { $0.name == "state" })?.value,
           let expected = pendingState, state != expected {
            throw APIError.authFailed("State mismatch — possible CSRF, aborting")
        }
        guard let verifier = pendingVerifier else {
            throw APIError.authFailed("No PKCE verifier in memory — flow not started")
        }

        defer {
            pendingVerifier = nil
            pendingState = nil
        }

        let tokens = try await repository.completeOAuth(
            code: code,
            codeVerifier: verifier,
            redirectURI: configuration.redirectURI
        )
        try await client.persist(tokens)
        logger.info("X OAuth complete — token persisted")
        return tokens
    }

    public func signOut() async throws {
        try await client.clearTokens()
        logger.info("Signed out — tokens cleared from Keychain")
    }
}
