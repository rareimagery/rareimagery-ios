import GoogleSignIn
import UIKit

/// Presents Google Sign-In and returns the ID token for BFF verification.
@MainActor
final class GoogleSignInController {

    enum Result: Sendable {
        case success(identityToken: String)
        case cancelled
        case failed(String)
    }

    func signIn(clientID: String, presenting viewController: UIViewController) async -> Result {
        guard !clientID.isEmpty else {
            return .failed("Google client ID is not configured in this build.")
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        do {
            let signInResult = try await GIDSignIn.sharedInstance.signIn(withPresenting: viewController)
            guard let token = signInResult.user.idToken?.tokenString, !token.isEmpty else {
                return .failed("Google did not return an ID token.")
            }
            return .success(identityToken: token)
        } catch {
            let ns = error as NSError
            if ns.domain == GIDSignInError.errorDomain,
               ns.code == GIDSignInError.canceled.rawValue {
                return .cancelled
            }
            return .failed(error.localizedDescription)
        }
    }
}
