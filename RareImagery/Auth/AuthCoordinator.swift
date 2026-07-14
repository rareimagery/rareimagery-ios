import Foundation
import UIKit
import AuthenticationServices
import RareImageryAPI

@MainActor
final class AuthCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {

    private let logger = APILogger(category: "AuthCoordinator")

    /// ADR-023 brokered sign-in (T-016). The user proves identity via X in
    /// the system browser; the BFF broker swaps the X code for a one-time
    /// Drupal x_login code; the app exchanges that at Drupal /oauth/token.
    /// The session lands as an oauth2_token row in Postgres. Drupal's own
    /// login page is never involved — that was the fatal flaw of the old
    /// authorize-URL flow this replaces (X users have no Drupal password).
    func signInWithDrupal(state: AppState) async {
        do {
            // 1. Drupal-leg PKCE — verifier stays inside AuthManager.
            let drupalChallenge = try await state.authManager.prepareBrokeredChallenge()

            // 2. X leg in the system browser (same as the legacy flow).
            let request = try await state.authService.startXAuth()
            let callbackURL = try await openWebSession(
                url: request.authorizationURL,
                scheme: request.callbackScheme
            )

            // 3. Broker: X code → one-time Drupal x_login code.
            let exchange = try await state.authService.exchangeForDrupalCode(
                callbackURL: callbackURL,
                drupalCodeChallenge: drupalChallenge,
                clientId: state.configuration.oauthClientID
            )

            // 4. Finish at Drupal /oauth/token.
            let tokens = try await state.authManager.completeBrokeredSignIn(
                drupalCode: exchange.drupalCode
            )

            // Clear anonymous trial state — production OAuth takes over.
            try? await state.keychain.clearAnonymousState()
            state.session.applyOAuthTokens(
                accessToken: tokens.accessToken,
                expiresAt: tokens.expiresAt
            )
            state.session.hasSeenLivePreview = false
            state.session.hasSeenFunnel = false
        } catch let error as APIError {
            logger.warning("Drupal sign-in failed: \(error.userFacingMessage)")
            state.session.setError(error.userFacingMessage)
        } catch {
            logger.error("Drupal sign-in unexpected error: \(error.localizedDescription)")
            state.session.setError(error.localizedDescription)
        }
    }

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
            // The pre-sign-in funnel draft is now claimed server-side. Promote
            // its uuid to `firstProductUuid` (instead of dropping it) so the
            // Creations tab can surface that video as the creator's first
            // product, editable + publishable.
            if let claimed = draftUuid, !claimed.isEmpty {
                try? await state.keychain.set(claimed, for: .firstProductUuid)
            }
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
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
            ?? scenes.compactMap { $0 as? UIWindowScene }.first
        if let window = windowScene?.windows.first(where: \.isKeyWindow) {
            return window
        }
        if let window = windowScene?.windows.first {
            return window
        }
        return ASPresentationAnchor()
    }

}
