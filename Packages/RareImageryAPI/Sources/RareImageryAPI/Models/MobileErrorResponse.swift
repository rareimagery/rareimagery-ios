import Foundation

/// Matches the rareimagery_api (Drupal) error envelope:
/// `{ "errors": [ { "status": "...", "code": "...", "detail": "..." } ] }`
public struct APIErrorEnvelope: Decodable, Sendable, Equatable {
    public struct Item: Decodable, Sendable, Equatable {
        public let status: String
        public let code: String
        public let detail: String

        public init(status: String, code: String, detail: String) {
            self.status = status
            self.code = code
            self.detail = detail
        }
    }

    public let errors: [Item]

    public init(errors: [Item]) {
        self.errors = errors
    }

    public var first: Item? { errors.first }
}

/// Matches the BFF's wrapped error envelope per CLAUDE.md §2.2:
///   `{ "error": { "code": "STRING_CODE", "message": "Human readable." } }`
///
/// Some legacy routes (e.g. `/api/products/from-images`, `/api/upload`) return a
/// **flat** shape instead: `{ "error": "Unauthorized" }`. Decoder accepts both.
public struct MobileErrorResponse: Codable, Sendable, Equatable {
    public struct Body: Codable, Sendable, Equatable {
        public let code: String?
        public let message: String?
    }
    public let error: Body?

    public var displayMessage: String {
        error?.message ?? "Something went wrong."
    }

    public var code: String? { error?.code }

    private enum CodingKeys: String, CodingKey { case error }

    public init(error: Body?) {
        self.error = error
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Preferred: nested object envelope
        if let body = try? container.decode(Body.self, forKey: .error) {
            self.error = body
            return
        }
        // Legacy: flat string under "error"
        if let flat = try? container.decode(String.self, forKey: .error) {
            self.error = Body(code: nil, message: flat)
            return
        }
        self.error = nil
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(error, forKey: .error)
    }
}

/// Known mobile error codes from CLAUDE.md §2.2 plus probed prod additions.
public enum MobileErrorCode: String, Sendable {
    case badRequest = "BAD_REQUEST"
    case xTokenExchangeFailed = "X_TOKEN_EXCHANGE_FAILED"
    case xUserFetchFailed = "X_USER_FETCH_FAILED"
    case drupalProvisionFailed = "DRUPAL_PROVISION_FAILED"
    case slugTaken = "SLUG_TAKEN"
    case reservedSlug = "RESERVED_SLUG"
    case serverMisconfigured = "SERVER_MISCONFIGURED"
    case internalError = "INTERNAL"
    case tokenMissing = "TOKEN_MISSING"
    case tokenExpired = "TOKEN_EXPIRED"
    case tokenInvalid = "TOKEN_INVALID"
    case wrongAudience = "WRONG_AUDIENCE"
    // Observed on production but not in the published spec — added 2026-05-22:
    case mobileAuthFailed = "MOBILE_AUTH_FAILED"     // shared-auth middleware on products endpoints
    case unauthorized = "UNAUTHORIZED"                 // shared-auth middleware "No session cookie..."
    case appleAuthNotReady = "APPLE_AUTH_NOT_READY"  // /api/mobile/auth/apple/callback stub
    // ADR-023 broker (/api/auth/x/exchange) + Drupal mint-code:
    case unknownClient = "UNKNOWN_CLIENT"
    case drupalMintFailed = "DRUPAL_MINT_FAILED"
    case drupalError = "DRUPAL_ERROR"
    case grantNotEnabled = "GRANT_NOT_ENABLED"
    case validationFailed = "VALIDATION_FAILED"
}
