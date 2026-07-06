import Foundation
import RareImageryAPI

@MainActor
@Observable
final class AuthSession {
    enum Status: Equatable {
        case checking
        case signedOut
        case signedIn(MobileClaims)
        /// Phase 3 — trial mode. The user has an anonymous JWT but no X
        /// identity. Allowed to hit `merch-ideas`; gated from
        /// `design-studio/generate` and any publish/store action.
        case anonymous(AnonymousClaims)
    }

    /// Total free vibe-photo merch-ideas calls per anonymous device.
    /// Soft client-side gate that drives the SignUpReminderBanner. Server
    /// has its own rate-limit safety net keyed by `anon:{deviceId}`.
    static let anonymousFreeUsesCap: Int = 3

    var status: Status = .checking
    var creator: AuthTokenResponse.Creator?
    /// Only meaningful when `status == .anonymous`. Decrements toward 0 as
    /// the trial user spends free merch-ideas calls. Persisted across app
    /// launches via `KeychainStore.anonymousFreeUsesUsed`.
    var freeUsesRemaining: Int = AuthSession.anonymousFreeUsesCap
    var lastError: String?

    /// Flag for the post-sign-in "You're live" screen (LivePreviewView).
    /// Starts false on each sign-in so freshly-signed-in users see the
    /// welcome screen; flips true once they pick one of its three CTAs,
    /// at which point ContentView routes them to the main app on the
    /// next render. Reset by `setSignedOut` so the next sign-in re-shows
    /// the welcome screen.
    var hasSeenLivePreview: Bool = false

    /// Flag for the value-first video funnel. Anonymous users see
    /// `VideoSubmissionFunnelView` on first launch until they skip or finish
    /// claiming. Reset on sign-out / fresh sign-in like `hasSeenLivePreview`.
    /// Not set in `setAnonymous` — trial users should see the funnel.
    var hasSeenFunnel: Bool = false

    var isSignedIn: Bool {
        if case .signedIn = status { return true }
        return false
    }

    /// True when the session is anonymous-trial. Used by OnePageCreator to
    /// show the SignUpReminderBanner and to gate the generation/publish CTAs
    /// behind a "Connect X" upgrade flow.
    var isAnonymous: Bool {
        if case .anonymous = status { return true }
        return false
    }

    /// True for either signedIn OR anonymous — meaning the app can make
    /// authenticated API calls. Routes that accept anonymous (currently
    /// only `merch-ideas`) work in both states; everything else 401s
    /// gracefully for anonymous and the UI prevents that path.
    var hasAnyToken: Bool {
        switch status {
        case .signedIn, .anonymous: return true
        default: return false
        }
    }

    var claims: MobileClaims? {
        if case .signedIn(let c) = status { return c }
        return nil
    }

    var anonymousClaims: AnonymousClaims? {
        if case .anonymous(let c) = status { return c }
        return nil
    }

    /// Phase 3 — true when the trial user has hit the soft sign-up
    /// reminder threshold. Drives the persistent banner in
    /// OnePageCreatorView.
    var shouldShowSignUpReminder: Bool {
        isAnonymous && freeUsesRemaining <= 0
    }

    /// True when the anonymous trial budget is exhausted — skip funnel, use shell gating.
    var trialExhausted: Bool { shouldShowSignUpReminder }

    /// Prefer the response's creator block when available; falls back to JWT claims.
    var displayHandle: String? {
        creator?.handle ?? claims?.handle
    }

    var storeUuid: String? {
        creator?.storeUuid ?? claims?.storeUuid
    }

    func apply(tokens: AuthTokenResponse) {
        do {
            let claims = try JWTDecoder.decode(tokens.accessToken)
            self.status = .signedIn(claims)
            self.creator = tokens.creator
            self.lastError = nil
            // Fresh sign-in always shows the live-preview welcome screen,
            // even if this is a returning user who previously dismissed it
            // on another device. Local-only flag — no server round-trip.
            self.hasSeenLivePreview = false
            self.hasSeenFunnel = false
            // Trial counter no longer applies to a signed-in session.
            // Phase 3: the anonymous JWT in `.accessToken` was just
            // overwritten by the production one; clear the counter so
            // a future anonymous re-bootstrap (e.g. after explicit
            // sign-out followed by reinstall scenarios) starts fresh.
            self.freeUsesRemaining = AuthSession.anonymousFreeUsesCap
        } catch {
            self.status = .signedOut
            self.lastError = "Token decode failed: \(error)"
        }
    }

    /// Phase 3 — bootstrap into trial mode. The anonymous JWT has already
    /// been written to `.accessToken` by `AppState.bootstrapAnonymous`;
    /// this just updates the session's observable status + counter so
    /// SwiftUI re-renders gated CTAs accordingly.
    func setAnonymous(claims: AnonymousClaims, freeUsesRemaining: Int) {
        self.status = .anonymous(claims)
        self.creator = nil
        self.freeUsesRemaining = freeUsesRemaining
        self.lastError = nil
        self.hasSeenLivePreview = true  // trial users skip the welcome screen
    }

    /// Phase 3 — decrement the soft counter after a successful merch-ideas
    /// call. Pairs with `AppState.recordAnonymousFreeUseSpent()` which
    /// persists the new value to Keychain. UI-only — the BFF rate-limit
    /// is the real enforcement.
    func decrementFreeUses() {
        freeUsesRemaining = max(0, freeUsesRemaining - 1)
    }

    func setSignedOut(error: String? = nil) {
        self.status = .signedOut
        self.creator = nil
        self.lastError = error
        self.hasSeenLivePreview = false
        self.hasSeenFunnel = false
        self.freeUsesRemaining = AuthSession.anonymousFreeUsesCap
    }

    func setError(_ message: String) {
        self.lastError = message
    }
}
