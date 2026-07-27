import AuthenticationServices
import Foundation

/// Presents Sign in with Apple and returns the native identity token + optional first-consent profile fields.
@MainActor
final class AppleSignInController: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {

    enum Result: Sendable {
        case success(identityToken: String, fullName: String?)
        case cancelled
        case failed(String)
    }

    private var continuation: CheckedContinuation<Result, Never>?

    func signIn() async -> Result {
        await withCheckedContinuation { cont in
            continuation = cont
            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            request.requestedScopes = [.fullName, .email]
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            continuation?.resume(returning: .failed("Unexpected Apple credential type."))
            continuation = nil
            return
        }
        guard let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8),
              !identityToken.isEmpty else {
            continuation?.resume(returning: .failed("Apple did not return an identity token."))
            continuation = nil
            return
        }
        var fullName: String?
        if let name = credential.fullName {
            let parts = [name.givenName, name.familyName].compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            let joined = parts.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if !joined.isEmpty { fullName = joined }
        }
        continuation?.resume(returning: .success(identityToken: identityToken, fullName: fullName))
        continuation = nil
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        if let authError = error as? ASAuthorizationError, authError.code == .canceled {
            continuation?.resume(returning: .cancelled)
        } else {
            continuation?.resume(returning: .failed(error.localizedDescription))
        }
        continuation = nil
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
            ?? scenes.compactMap { $0 as? UIWindowScene }.first
        return windowScene?.windows.first(where: \.isKeyWindow)
            ?? windowScene?.windows.first
            ?? ASPresentationAnchor()
    }
}
