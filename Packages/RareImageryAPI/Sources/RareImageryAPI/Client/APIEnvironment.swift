import Foundation

/// Drupal / rareimagery_api URL surface.
///
/// Host comes from `APIConfiguration.baseURL` (xcconfig) — never hardcode
/// per-store subdomains here. Default production host for Drupal is
/// `https://rareimagery.net` once Debug.xcconfig is retargeted off the BFF.
public enum APIEnvironment: Sendable {
    /// Canonical production Drupal host (reference only — prefer `urls(for:)`).
    public static let productionBaseURL = URL(string: "https://rareimagery.net")!

    public static func urls(for baseURL: URL) -> Endpoints {
        Endpoints(baseURL: baseURL)
    }

    public struct Endpoints: Sendable {
        public let baseURL: URL

        public var jsonAPI: URL { baseURL.appending(path: "jsonapi") }
        public var apiV1: URL { baseURL.appending(path: "api/v1") }
        public var oauthToken: URL { baseURL.appending(path: "oauth/token") }
        public var oauthAuthorize: URL { baseURL.appending(path: "oauth/authorize") }
    }
}

extension APIConfiguration {
    public var endpoints: APIEnvironment.Endpoints {
        APIEnvironment.urls(for: baseURL)
    }
}
