import Foundation
import RareImageryAPI

@MainActor
@Observable
final class AuthSession {
    enum Status: Equatable {
        case checking
        case signedOut
        case signedIn(MobileClaims)
    }

    var status: Status = .checking
    var creator: AuthTokenResponse.Creator?
    var lastError: String?

    /// Flag for the post-sign-in "You're live" screen (LivePreviewView).
    /// Starts false on each sign-in so freshly-signed-in users see the
    /// welcome screen; flips true once they pick one of its three CTAs,
    /// at which point ContentView routes them to the main app on the
    /// next render. Reset by `setSignedOut` so the next sign-in re-shows
    /// the welcome screen.
    var hasSeenLivePreview: Bool = false

    var isSignedIn: Bool {
        if case .signedIn = status { return true }
        return false
    }

    var claims: MobileClaims? {
        if case .signedIn(let c) = status { return c }
        return nil
    }

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
        } catch {
            self.status = .signedOut
            self.lastError = "Token decode failed: \(error)"
        }
    }

    func setSignedOut(error: String? = nil) {
        self.status = .signedOut
        self.creator = nil
        self.lastError = error
        self.hasSeenLivePreview = false
    }

    func setError(_ message: String) {
        self.lastError = message
    }
}
