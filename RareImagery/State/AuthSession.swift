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
    var lastError: String?

    var isSignedIn: Bool {
        if case .signedIn = status { return true }
        return false
    }

    var claims: MobileClaims? {
        if case .signedIn(let c) = status { return c }
        return nil
    }

    func apply(tokens: AuthTokenResponse) {
        do {
            let claims = try JWTDecoder.decode(tokens.accessToken)
            self.status = .signedIn(claims)
            self.lastError = nil
        } catch {
            self.status = .signedOut
            self.lastError = "Token decode failed: \(error)"
        }
    }

    func setSignedOut(error: String? = nil) {
        self.status = .signedOut
        self.lastError = error
    }

    func setError(_ message: String) {
        self.lastError = message
    }
}
