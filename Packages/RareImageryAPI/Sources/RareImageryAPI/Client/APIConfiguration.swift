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
