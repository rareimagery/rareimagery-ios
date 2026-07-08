import Foundation

/// Request body for `POST /api/v1/vision/value` — the anonymous, pre-login
/// valuation endpoint used by the value-first video funnel. No Authorization
/// header; identity is `deviceId` alone (rate-limited server-side).
///
/// `imageUrls` are JPEG base64 data URLs (`data:image/jpeg;base64,...`),
/// 1-4 entries — same convention as `ProductRepository.analyze`. The route
/// only ever scores the first entry (hero-only, always, for anonymous
/// callers) — sending more is harmless but wasted bandwidth.
///
/// `source` is optional ("photo" | "video") and controls transcript
/// tagging server-side; the video funnel should always pass "video".
public struct AnonymousValueRequest: Encodable, Sendable {
    public let imageUrls: [String]
    public let voiceTranscript: String?
    public let deviceId: String
    public let source: String?

    public init(imageUrls: [String], voiceTranscript: String? = nil, deviceId: String, source: String? = nil) {
        self.imageUrls = imageUrls
        self.voiceTranscript = voiceTranscript
        self.deviceId = deviceId
        self.source = source
    }
}

/// Response from `POST /api/v1/vision/value`.
///
/// `draft` reuses the shared `ProductDraft` model — the same shape the
/// authenticated `/api/vision/analyze` endpoint returns — per the contract:
/// anonymous valuation is not a parallel data shape, just a different auth
/// mode on the same underlying draft concept.
///
/// `draftUuid` is a Drupal product uuid (or `nil` if the BFF didn't persist
/// a draft for this call). When present, thread it through the X OAuth
/// callback's optional `draftUuid` field so the backend can claim this
/// specific draft into the new creator's store.
public struct AnonymousValueResponse: Decodable, Sendable, Equatable {
    public let ok: Bool
    public let draft: ProductDraft
    public let draftUuid: String?
    public let model: String?

    public init(ok: Bool, draft: ProductDraft, draftUuid: String? = nil, model: String? = nil) {
        self.ok = ok
        self.draft = draft
        self.draftUuid = draftUuid
        self.model = model
    }
}
