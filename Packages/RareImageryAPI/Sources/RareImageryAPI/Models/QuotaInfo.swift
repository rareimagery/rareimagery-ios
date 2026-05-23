import Foundation

/// Surfaced when a Phase-M `CreatorTierGate` AI quota is exhausted (HTTP 402).
/// Endpoint contract (per Drupal/BFF handoff 2026-05-23):
///   { "error": "quota_exceeded", "tier": "...", "used": N, "limit": N, "resets_at": <unix> }
public struct QuotaInfo: Decodable, Sendable, Equatable {
    public let tier: String
    public let used: Int
    public let limit: Int
    public let resetsAt: Int

    enum CodingKeys: String, CodingKey {
        case tier, used, limit
        case resetsAt = "resets_at"
    }

    public var resetsAtDate: Date {
        Date(timeIntervalSince1970: TimeInterval(resetsAt))
    }
}

/// Internal envelope used to identify a quota-exceeded body before mapping
/// into `APIError.quotaExceeded`.
struct QuotaErrorBody: Decodable {
    let error: String?
    let tier: String?
    let used: Int?
    let limit: Int?
    let resetsAt: Int?

    enum CodingKeys: String, CodingKey {
        case error, tier, used, limit
        case resetsAt = "resets_at"
    }
}
