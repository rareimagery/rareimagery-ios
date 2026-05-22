import Foundation
import AuthenticationServices
import RareImageryAPI

@MainActor
final class AuthCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {

    func signInWithX(state: AppState) async {
        do {
            let request = try await state.authService.startXAuth()
            let callbackURL = try await openWebSession(
                url: request.authorizationURL,
                scheme: request.callbackScheme
            )
            let tokens = try await state.authService.completeXAuth(callbackURL: callbackURL)
            state.session.apply(tokens: tokens)
        } catch APIError.authCancelled {
            state.session.setError("Sign-in cancelled.")
        } catch {
            state.session.setError(prettyError(error))
        }
    }

    private func openWebSession(url: URL, scheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: scheme
            ) { callback, error in
                if let error = error {
                    if let asError = error as? ASWebAuthenticationSessionError,
                       asError.code == .canceledLogin {
                        cont.resume(throwing: APIError.authCancelled)
                    } else {
                        cont.resume(throwing: APIError.authFailed(error.localizedDescription))
                    }
                    return
                }
                guard let callback = callback else {
                    cont.resume(throwing: APIError.authFailed("No callback URL"))
                    return
                }
                cont.resume(returning: callback)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            if !session.start() {
                cont.resume(throwing: APIError.authFailed("ASWebAuthenticationSession.start returned false"))
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        ASPresentationAnchor()
    }

    private func prettyError(_ error: Error) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case .invalidConfiguration(let msg): return "Config error: \(msg)"
            case .authFailed(let msg): return msg
            case .unauthorized: return "Unauthorized — please try again."
            case .network: return "Network error — check your connection."
            default: return "\(apiError)"
            }
        }
        return error.localizedDescription
    }
}
