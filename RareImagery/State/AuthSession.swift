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
        } catch {
            self.status = .signedOut
            self.lastError = "Token decode failed: \(error)"
        }
    }

    func setSignedOut(error: String? = nil) {
        self.status = .signedOut
        self.creator = nil
        self.lastError = error
    }

    func setError(_ message: String) {
        self.lastError = message
    }
}
