import Foundation
import AuthenticationServices
import RareImageryAPI

@MainActor
final class AuthCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {

    private let logger = APILogger(category: "AuthCoordinator")

    func signInWithX(state: AppState, draftToken: String? = nil, draftUuid: String? = nil) async {
        do {
            let request = try await state.authService.startXAuth()
            let callbackURL = try await openWebSession(
                url: request.authorizationURL,
                scheme: request.callbackScheme
            )
            // deviceId always rides along when we have one — it lets the
            // backend correlate anonymous activity with the claiming
            // creator even when there's no specific draftUuid to claim.
            let deviceId = try? await state.keychain.stableDeviceId()
            let tokens = try await state.authService.completeXAuth(
                callbackURL: callbackURL,
                draftToken: draftToken,
                draftUuid: draftUuid,
                deviceId: deviceId
            )
            state.session.apply(tokens: tokens)
            // Clear any pending draft claim state now that X auth succeeded (draft linked server-side).
            try? await state.keychain.remove(.pendingDraftToken)
            try? await state.keychain.remove(.pendingDraftUuid)
        } catch let error as APIError {
            if let code = error.code {
                logger.warning("X sign-in failed: code=\(code.rawValue), reason=\(error.userFacingMessage)")
            } else {
                logger.warning("X sign-in failed: \(error.userFacingMessage)")
            }
            state.session.setError(error.userFacingMessage)
        } catch {
            logger.error("X sign-in unexpected error: \(error.localizedDescription)")
            state.session.setError(error.localizedDescription)
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

}
