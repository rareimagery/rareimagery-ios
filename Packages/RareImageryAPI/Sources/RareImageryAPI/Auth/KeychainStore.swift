import Foundation
import Security

public actor KeychainStore {
    public enum Failure: Error {
        case status(OSStatus)
        case notFound
        case encoding
    }

    public enum Key: String, Sendable {
        case accessToken = "ri.access_token"
        case refreshToken = "ri.refresh_token"
        case accessTokenExpiry = "ri.access_token_expiry"

        // Phase 3 — anonymous trial mode.
        // `anonymousDeviceId` is the client-generated UUID that the BFF
        // rate-limits by; it survives across token refreshes and ideally
        // across app launches so a returning trial user keeps the same
        // device identity (and thus their already-spent counter).
        // `anonymousFreeUsesUsed` is the per-device counter for the
        // soft sign-up reminder (decimal string, "0" through "3+").
        // Cleared explicitly on X sign-in via `clearAnonymousState()`.
        case anonymousDeviceId = "ri.anonymous_device_id"
        case anonymousFreeUsesUsed = "ri.anonymous_free_uses_used"

        // Phase 3.5 — value-first draft claim handoff.
        // `pendingDraftToken` holds the draft-claim JWT returned by anonymous
        // vision analysis. Persisted so it survives restart; passed through
        // x/callback then cleared on successful claim.
        case pendingDraftToken = "ri.pending_draft_token"

        // `pendingDraftUuid` — companion to `pendingDraftToken` for the
        // POST /api/v1/vision/value contract: the anonymous valuation
        // response returns a Drupal product uuid (`draftUuid`) instead of
        // a JWT. Threaded through the X OAuth callback's optional
        // `draftUuid` field so the backend can attach the claimed draft to
        // the new creator. Cleared alongside `pendingDraftToken` on claim.
        case pendingDraftUuid = "ri.pending_draft_uuid"

        // `deviceId` — a stable UUID minted once per install and reused
        // forever (unlike `anonymousDeviceId`, which is cleared on sign-out
        // via `clearAnonymousState()`). This is the identity the anonymous
        // valuation endpoint (`/api/v1/vision/value`) rate-limits by, and it
        // is threaded through the X OAuth callback so the backend can
        // correlate anonymous activity with the claiming creator even
        // across a sign-out/sign-in cycle. Deliberately NOT cleared by
        // `clearAll()` or `clearAnonymousState()`.
        case deviceId = "ri.device_id"

        // `firstProductUuid` — set from the pre-sign-in funnel draft once it
        // is claimed at sign-in, so the app can surface that video/valuation
        // as the creator's first product (editable + publishable). Distinct
        // from `pendingDraftUuid`, which is consumed by the claim itself.
        case firstProductUuid = "ri.first_product_uuid"
    }

    private let service: String

    public init(service: String = "com.rareimagery.studio") {
        self.service = service
    }

    public func set(_ value: String, for key: Key) throws {
        guard let data = value.data(using: .utf8) else { throw Failure.encoding }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw Failure.status(addStatus) }
        } else if status != errSecSuccess {
            throw Failure.status(status)
        }
    }

    public func get(_ key: Key) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let string = String(data: data, encoding: .utf8) else {
                return nil
            }
            return string
        case errSecItemNotFound:
            return nil
        default:
            throw Failure.status(status)
        }
    }

    public func remove(_ key: Key) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Failure.status(status)
        }
    }

    public func clearAll() throws {
        for key in [Key.accessToken, .refreshToken, .accessTokenExpiry] {
            try remove(key)
        }
    }

    /// Phase 3 — clear anonymous-trial state. Called when a trial user
    /// successfully X-auths to leave a clean slate (the production
    /// tokens take over via `.accessToken`/.refreshToken`). Idempotent.
    /// Deliberately NOT part of `clearAll` so a sign-out doesn't
    /// re-arm the free trial — once a user has converted, returning to
    /// trial would be misleading.
    public func clearAnonymousState() throws {
        try remove(.anonymousDeviceId)
        try remove(.anonymousFreeUsesUsed)
    }

    /// Returns the stable per-install device id used for anonymous
    /// valuation (`POST /api/v1/vision/value`), minting and persisting one
    /// on first call if none exists yet. Distinct from `.anonymousDeviceId`
    /// (the anonymous-auth-session identity, which is cleared on sign-out) —
    /// this id is meant to outlive sign-in/sign-out cycles.
    public func stableDeviceId() throws -> String {
        if let existing = try get(.deviceId), !existing.isEmpty {
            return existing
        }
        let fresh = UUID().uuidString.lowercased()
        try set(fresh, for: .deviceId)
        return fresh
    }
}
