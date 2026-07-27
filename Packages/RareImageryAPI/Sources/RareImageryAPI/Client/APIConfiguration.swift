import Foundation

public struct APIConfiguration: Sendable {
    public let baseURL: URL
    public let xClientID: String
    public let xCallbackScheme: String
    public let xCallbackPath: String
    /// simple_oauth consumer UUID (public client). From Phase D-A.
    public let oauthClientID: String
    /// Google OAuth iOS client ID (native sign-in). Phase multi-provider.
    public let googleIOSClientID: String
    /// Drupal OAuth redirect — must match the consumer redirect URI.
    public let oauthCallbackPath: String
    public let environment: String

    public var redirectURI: String {
        "\(xCallbackScheme)://auth\(xCallbackPath)"
    }

    /// Authorization-code + PKCE redirect for Drupal simple_oauth.
    public var oauthRedirectURI: String {
        "\(xCallbackScheme)://oauth\(oauthCallbackPath)"
    }

    /// True when a real X OAuth 2.0 Client ID is wired (not xcconfig placeholders).
    public var isXClientIDConfigured: Bool {
        Self.isConfiguredClientID(xClientID, placeholders: [
            "REPLACE_ME",
            "paste_your",
            "your_x_oauth",
            "YOUR_X_CLIENT",
            "paste your"
        ])
    }

    /// True when the Drupal simple_oauth consumer UUID is wired (not VERIFY placeholder).
    public var isOAuthClientConfigured: Bool {
        Self.isConfiguredClientID(oauthClientID, placeholders: [
            "VERIFY",
            "REPLACE_ME",
            "paste_your",
            "YOUR_OAUTH",
            "CONSUMER-UUID"
        ])
    }

    /// True when Google native sign-in client ID is wired.
    public var isGoogleClientConfigured: Bool {
        Self.isConfiguredClientID(googleIOSClientID, placeholders: [
            "REPLACE_ME",
            "paste_your",
            "YOUR_GOOGLE",
            "GOOGLE_IOS"
        ])
    }

    public init(
        baseURL: URL,
        xClientID: String,
        xCallbackScheme: String = "rareimagery",
        xCallbackPath: String = "/callback",
        oauthClientID: String = "",
        googleIOSClientID: String = "",
        oauthCallbackPath: String = "/callback",
        environment: String = "production"
    ) {
        self.baseURL = baseURL
        self.xClientID = xClientID
        self.xCallbackScheme = xCallbackScheme
        self.xCallbackPath = xCallbackPath
        self.oauthClientID = oauthClientID
        self.googleIOSClientID = googleIOSClientID
        self.oauthCallbackPath = oauthCallbackPath
        self.environment = environment
    }

    public static var fromBundle: APIConfiguration {
        let info = Bundle.main.infoDictionary ?? [:]
        let rawBase = (info["APIBaseURL"] as? String) ?? "https://www.rareimagery.net"
        // Require a host, not just a parseable URL: the xcconfig comment trap
        // ("https://host" truncating to "https:") yields a non-nil URL whose
        // requests resolve against relative hostnames like "api".
        let baseURL: URL
        if let parsed = URL(string: rawBase), parsed.host != nil {
            baseURL = parsed
        } else {
            baseURL = URL(string: "https://www.rareimagery.net")!
        }
        let xClient = (info["XClientID"] as? String) ?? ""
        let oauthClient = (info["OAuthClientID"] as? String) ?? ""
        let googleClient = (info["GoogleIOSClientID"] as? String) ?? ""
        let env = (info["Environment"] as? String) ?? "production"
        return APIConfiguration(
            baseURL: baseURL,
            xClientID: xClient,
            oauthClientID: oauthClient,
            googleIOSClientID: googleClient,
            environment: env
        )
    }

    private static func isConfiguredClientID(_ raw: String, placeholders: [String]) -> Bool {
        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return false }
        return !placeholders.contains { id.localizedCaseInsensitiveContains($0) }
    }
}
