import Foundation

public struct APIConfiguration: Sendable {
    public let baseURL: URL
    public let xClientID: String
    public let xCallbackScheme: String
    public let xCallbackPath: String
    public let environment: String

    public var redirectURI: String {
        "\(xCallbackScheme)://auth\(xCallbackPath)"
    }

    /// True when a real X OAuth 2.0 Client ID is wired (not xcconfig placeholders).
    public var isXClientIDConfigured: Bool {
        let id = xClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return false }
        let placeholders = [
            "REPLACE_ME",
            "paste_your",
            "your_x_oauth",
            "YOUR_X_CLIENT",
            "paste your"
        ]
        return !placeholders.contains { id.localizedCaseInsensitiveContains($0) }
    }

    public init(
        baseURL: URL,
        xClientID: String,
        xCallbackScheme: String = "rareimagery",
        xCallbackPath: String = "/callback",
        environment: String = "production"
    ) {
        self.baseURL = baseURL
        self.xClientID = xClientID
        self.xCallbackScheme = xCallbackScheme
        self.xCallbackPath = xCallbackPath
        self.environment = environment
    }

    public static var fromBundle: APIConfiguration {
        let info = Bundle.main.infoDictionary ?? [:]
        let rawBase = (info["APIBaseURL"] as? String) ?? "https://www.rareimagery.net"
        let baseURL = URL(string: rawBase) ?? URL(string: "https://www.rareimagery.net")!
        let xClient = (info["XClientID"] as? String) ?? ""
        let env = (info["Environment"] as? String) ?? "production"
        return APIConfiguration(baseURL: baseURL, xClientID: xClient, environment: env)
    }
}
