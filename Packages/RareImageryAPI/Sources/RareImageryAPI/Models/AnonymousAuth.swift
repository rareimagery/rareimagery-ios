import Foundation

/// Request body for POST /api/mobile/auth/anonymous.
/// `deviceId` is a client-generated UUID v4 persisted in iOS Keychain so
/// the SAME identity is reused across app launches (preserves rate-limit
/// bucket + free-uses counter on the BFF side).
public struct AnonymousAuthRequest: Encodable, Sendable {
    public let deviceId: String

    public init(deviceId: String) {
        self.deviceId = deviceId
    }

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
    }
}

/// Response from POST /api/mobile/auth/anonymous.
/// The token is a short-lived (24h per BFF spec) JWT with audience
/// `mobile-anonymous` — it CANNOT pass the standard `requireSessionOrMobile`
/// gate, only the broader `requireAnyAuthOrAnonymous` used by routes that
/// opted in (currently just `/api/v1/vision/merch-ideas`).
public struct AnonymousAuthResponse: Decodable, Sendable, Equatable {
    public let accessToken: String
    public let expiresIn: Int    // seconds from issuance
    public let tokenType: String // "Bearer"
    public let deviceId: String  // echoed back from request

    /// Convenience: when the token expires (computed at decode time, so
    /// caller doesn't need to know about the original request moment).
    public var expiresAt: Date {
        Date().addingTimeInterval(TimeInterval(expiresIn))
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
        case deviceId = "device_id"
    }
}

/// iOS-side projection of the anonymous JWT's payload. We don't actually
/// decode the JWT signature on the client (server-side is the only trust
/// boundary) — these claims are synthesized from the `AnonymousAuthResponse`
/// so AuthSession has a uniform "claims" surface across signed-in and
/// anonymous states.
public struct AnonymousClaims: Codable, Sendable, Equatable {
    /// Always `anon:{deviceId}` — matches what the BFF sets as JWT `sub`.
    public let sub: String
    public let deviceId: String
    /// Unix timestamp (seconds since epoch) — used to detect when the
    /// 24h token has aged out and a fresh one should be minted.
    public let exp: Int

    public init(deviceId: String, exp: Int) {
        self.sub = "anon:\(deviceId)"
        self.deviceId = deviceId
        self.exp = exp
    }

    public var expiresAt: Date { Date(timeIntervalSince1970: TimeInterval(exp)) }
    public var isExpired: Bool { expiresAt <= Date() }
}
