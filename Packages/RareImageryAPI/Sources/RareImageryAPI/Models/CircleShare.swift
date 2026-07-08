import Foundation

/// Intent passed to POST /api/v1/circle/share.
/// Drives copy + (future) notification template selection on the BFF side.
public enum ShareIntent: String, Codable, Sendable {
    case feedback
    case promote
}

/// Request body for POST /api/v1/circle/share.
///
/// - `draftId`: a UUID correlation ID for this share. In v1 the iOS client
///   generates this fresh per send because `ProductDraft` is not yet
///   persisted server-side with its own id. When draft persistence lands,
///   the real draft uuid flows in here instead.
/// - `recipientIds`: X numeric user IDs (e.g. "1234567890"). 1..24, matches
///   `CircleService.maxCircleSize`.
/// - `note`: optional creator message. BFF defaults to "What do you think
///   of this drop?" if absent/empty.
public struct CircleShareRequest: Encodable, Sendable {
    public let draftId: String
    public let recipientIds: [String]
    public let note: String?
    public let intent: ShareIntent

    public init(
        draftId: String,
        recipientIds: [String],
        note: String?,
        intent: ShareIntent
    ) {
        self.draftId = draftId
        self.recipientIds = recipientIds
        self.note = note
        self.intent = intent
    }
}

/// Per-recipient outcome from the BFF. Codes are stable — the iOS sheet
/// keys off them for the F3 partial-success recovery copy.
public struct RecipientResult: Decodable, Sendable, Identifiable {
    public enum Status: String, Decodable, Sendable {
        case sent
        case failed
    }

    public enum FailureReason: String, Decodable, Sendable {
        case network
        case recipientBlocked = "recipient_blocked"
        case recipientUnknown = "recipient_unknown"
        case rateLimited = "rate_limited"
        case `internal`
    }

    public let recipientId: String
    public let status: Status
    public let reason: FailureReason?

    public var id: String { recipientId }

    public init(recipientId: String, status: Status, reason: FailureReason? = nil) {
        self.recipientId = recipientId
        self.status = status
        self.reason = reason
    }
}

/// Response from POST /api/v1/circle/share.
/// 200 when any recipient succeeded (use `failed > 0` to detect partial);
/// 502 when every recipient failed (handled in the repository, not here).
public struct CircleShareResponse: Decodable, Sendable {
    public let ok: Bool
    public let intent: ShareIntent
    public let sent: Int
    public let failed: Int
    public let results: [RecipientResult]
    public let message: String

    public init(
        ok: Bool,
        intent: ShareIntent,
        sent: Int,
        failed: Int,
        results: [RecipientResult],
        message: String
    ) {
        self.ok = ok
        self.intent = intent
        self.sent = sent
        self.failed = failed
        self.results = results
        self.message = message
    }
}
