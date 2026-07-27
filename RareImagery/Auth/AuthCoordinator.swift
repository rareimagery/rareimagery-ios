import Foundation
import UIKit
import AuthenticationServices
import RareImageryAPI

@MainActor
final class AuthCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {

    private let logger = APILogger(category: "AuthCoordinator")
    private let appleSignIn = AppleSignInController()
    private let googleSignIn = GoogleSignInController()

    /// Called when Apple/Google exchange returns NEEDS_SLUG. Return the chosen slug or nil to cancel.
    var slugPicker: ((AuthService.ProviderSlugRequired, String) async -> String?)?

    /// ADR-023 brokered sign-in (T-016). The user proves identity via X in
    /// the system browser; the BFF broker swaps the X code for a one-time
    /// Drupal x_login code; the app exchanges that at Drupal /oauth/token.
    /// The session lands as an oauth2_token row in Postgres. Drupal's own
    /// login page is never involved — that was the fatal flaw of the old
    /// authorize-URL flow this replaces (X users have no Drupal password).
    ///
    /// When `OAUTH_CLIENT_ID` is configured, this is the default X sign-in
    /// path. The legacy BFF `/api/mobile/auth/x/callback` JWT mint is kept
    /// only for builds without a Drupal consumer, or when a pending draft
    /// claim must ride along (broker exchange doesn't accept draft params yet).
    func signInWithX(
        state: AppState,
        draftToken: String? = nil,
        draftUuid: String? = nil
    ) async {
        let needsLegacyDraftHandoff =
            (draftToken?.isEmpty == false) || (draftUuid?.isEmpty == false)
        if state.configuration.isOAuthClientConfigured && !needsLegacyDraftHandoff {
            await signInWithDrupal(state: state)
        } else {
            await signInWithLegacyMobileJWT(
                state: state,
                draftToken: draftToken,
                draftUuid: draftUuid
            )
        }
    }

    func signInWithApple(state: AppState) async {
        guard state.configuration.isOAuthClientConfigured else {
            state.session.setSignInFailure(
                AuthSession.SignInDiagnostic.from(
                    configuration: state.configuration,
                    path: "apple",
                    code: "SERVER_MISCONFIGURED",
                    detail: "Drupal OAuth client is not configured."
                )
            )
            return
        }
        let appleResult = await appleSignIn.signIn()
        switch appleResult {
        case .cancelled:
            return
        case .failed(let message):
            state.session.setSignInFailure(
                AuthSession.SignInDiagnostic.from(
                    configuration: state.configuration,
                    path: "apple",
                    code: nil,
                    detail: message
                )
            )
            return
        case .success(let identityToken, let fullName):
            await completeProviderBroker(
                state: state,
                path: "/api/auth/apple/exchange",
                identityToken: identityToken,
                fullName: fullName,
                signInPath: "apple"
            ) { token, challenge, clientId in
                try await state.authService.exchangeAppleForDrupalCode(
                    identityToken: token,
                    fullName: fullName,
                    drupalCodeChallenge: challenge,
                    clientId: clientId
                )
            } slugPick: { ticket, slug, challenge, clientId in
                try await state.authService.completeProviderSlugPick(
                    path: "/api/auth/apple/exchange",
                    ticket: ticket,
                    slug: slug,
                    drupalCodeChallenge: challenge,
                    clientId: clientId
                )
            }
        }
    }

    func signInWithGoogle(state: AppState, presenting viewController: UIViewController) async {
        guard state.configuration.isOAuthClientConfigured else {
            state.session.setSignInFailure(
                AuthSession.SignInDiagnostic.from(
                    configuration: state.configuration,
                    path: "google",
                    code: "SERVER_MISCONFIGURED",
                    detail: "Drupal OAuth client is not configured."
                )
            )
            return
        }
        guard state.configuration.isGoogleClientConfigured else {
            state.session.setSignInFailure(
                AuthSession.SignInDiagnostic.from(
                    configuration: state.configuration,
                    path: "google",
                    code: "SERVER_MISCONFIGURED",
                    detail: "Google client ID is not configured in this build."
                )
            )
            return
        }
        let googleResult = await googleSignIn.signIn(
            clientID: state.configuration.googleIOSClientID,
            presenting: viewController
        )
        switch googleResult {
        case .cancelled:
            return
        case .failed(let message):
            state.session.setSignInFailure(
                AuthSession.SignInDiagnostic.from(
                    configuration: state.configuration,
                    path: "google",
                    code: nil,
                    detail: message
                )
            )
            return
        case .success(let identityToken):
            await completeProviderBroker(
                state: state,
                path: "/api/auth/google/exchange",
                identityToken: identityToken,
                fullName: nil,
                signInPath: "google"
            ) { token, challenge, clientId in
                try await state.authService.exchangeGoogleForDrupalCode(
                    identityToken: token,
                    drupalCodeChallenge: challenge,
                    clientId: clientId
                )
            } slugPick: { ticket, slug, challenge, clientId in
                try await state.authService.completeProviderSlugPick(
                    path: "/api/auth/google/exchange",
                    ticket: ticket,
                    slug: slug,
                    drupalCodeChallenge: challenge,
                    clientId: clientId
                )
            }
        }
    }

    private func completeProviderBroker(
        state: AppState,
        path: String,
        identityToken: String,
        fullName: String?,
        signInPath: String,
        exchange: (_ identityToken: String, _ challenge: String, _ clientId: String) async throws -> AuthService.ProviderExchangeOutcome,
        slugPick: (_ ticket: String, _ slug: String, _ challenge: String, _ clientId: String) async throws -> AuthService.DrupalExchange
    ) async {
        do {
            let challenge = try await state.authManager.prepareBrokeredChallenge()
            let clientId = state.configuration.oauthClientID
            let outcome = try await exchange(identityToken, challenge, clientId)
            let drupalExchange: AuthService.DrupalExchange
            switch outcome {
            case .completed(let ex):
                drupalExchange = ex
            case .needsSlug(let req):
                guard let picker = slugPicker else {
                    throw APIError.authFailed("Slug picker not configured.")
                }
                guard let slug = await picker(req, path) else {
                    return
                }
                drupalExchange = try await slugPick(req.ticket, slug, challenge, clientId)
            }
            let tokens = try await state.authManager.completeBrokeredSignIn(
                drupalCode: drupalExchange.drupalCode
            )
            try? await state.keychain.clearAnonymousState()
            state.session.applyOAuthTokens(
                accessToken: tokens.accessToken,
                expiresAt: tokens.expiresAt,
                creator: drupalExchange.creator.map {
                    AuthTokenResponse.Creator(
                        profileUuid: $0.profileUuid,
                        storeUuid: $0.storeUuid,
                        slug: $0.slug,
                        handle: $0.handle,
                        displayName: $0.displayName,
                        avatarUrl: $0.avatarUrl,
                        role: "CREATOR"
                    )
                }
            )
            state.session.hasSeenLivePreview = false
            state.session.hasSeenFunnel = false
        } catch let error as APIError {
            recordSignInFailure(error, path: signInPath, state: state)
        } catch {
            logger.error("\(signInPath) sign-in unexpected error: \(error.localizedDescription)")
            state.session.setSignInFailure(
                AuthSession.SignInDiagnostic.from(
                    configuration: state.configuration,
                    path: signInPath,
                    code: nil,
                    detail: error.localizedDescription
                )
            )
        }
    }

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
                expiresAt: tokens.expiresAt,
                creator: exchange.creator.map {
                    AuthTokenResponse.Creator(
                        profileUuid: $0.profileUuid,
                        storeUuid: $0.storeUuid,
                        slug: $0.slug,
                        handle: $0.handle,
                        displayName: $0.displayName,
                        avatarUrl: $0.avatarUrl,
                        role: "CREATOR"
                    )
                }
            )
            state.session.hasSeenLivePreview = false
            state.session.hasSeenFunnel = false
        } catch let error as APIError {
            recordSignInFailure(error, path: "drupal", state: state)
        } catch {
            logger.error("Drupal sign-in unexpected error: \(error.localizedDescription)")
            let detail = error.localizedDescription
            state.session.setSignInFailure(
                AuthSession.SignInDiagnostic.from(
                    configuration: state.configuration,
                    path: "drupal",
                    code: nil,
                    detail: detail
                )
            )
        }
    }

    /// Legacy mobile-JWT path — `POST /api/mobile/auth/x/callback`.
    private func signInWithLegacyMobileJWT(
        state: AppState,
        draftToken: String? = nil,
        draftUuid: String? = nil
    ) async {
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
            recordSignInFailure(error, path: "legacy-x-callback", state: state)
        } catch {
            logger.error("X sign-in unexpected error: \(error.localizedDescription)")
            let detail = error.localizedDescription
            state.session.setSignInFailure(
                AuthSession.SignInDiagnostic.from(
                    configuration: state.configuration,
                    path: "legacy-x-callback",
                    code: nil,
                    detail: detail
                )
            )
        }
    }

    private func recordSignInFailure(_ error: APIError, path: String, state: AppState) {
        if let code = error.code {
            logger.warning("Sign-in (\(path)) failed: code=\(code.rawValue) message=\(error.userFacingMessage)")
        } else {
            logger.warning("Sign-in (\(path)) failed: \(error.userFacingMessage)")
        }
        let detail = Self.message(for: error)
        let codeString = error.code?.rawValue ?? Self.extractCode(from: error)
        state.session.setSignInFailure(
            AuthSession.SignInDiagnostic.from(
                configuration: state.configuration,
                path: path,
                code: codeString,
                detail: detail
            )
        )
    }

    private static func extractCode(from error: APIError) -> String? {
        switch error {
        case .authFailed(let message):
            if message.hasPrefix("X returned error:") { return "X_OAUTH_ERROR" }
            if message.contains("PKCE verifier") { return "PKCE_VERIFIER_LOST" }
            if message.contains("State mismatch") { return "STATE_MISMATCH" }
            return nil
        case .decode:
            return "DECODE_ERROR"
        case .notFound:
            return "NOT_FOUND"
        default:
            return nil
        }
    }

    /// User-visible copy — include error code when the server message is generic.
    private static func message(for error: APIError) -> String {
        let text = error.userFacingMessage
        guard let code = error.code else { return text }
        let generic = text.isEmpty
            || text == "Something went wrong."
            || text == "Something went wrong on our end. Please try again."
        if generic {
            return "Sign-in failed (\(code.rawValue)). Please try again."
        }
        return text
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

    /// Link X enrichment for Apple/Google creators (Phase E). Returns handle on success.
    func linkXAccount(state: AppState) async -> String? {
        do {
            let request = try await state.authService.startXAuth(scopes: ["tweet.read", "users.read"])
            let callbackURL = try await openWebSession(
                url: request.authorizationURL,
                scheme: request.callbackScheme
            )
            return try await state.authService.linkXAccount(callbackURL: callbackURL)
        } catch let error as APIError where error == .authCancelled {
            return nil
        } catch {
            logger.warning("Link X failed: \(error.localizedDescription)")
            state.session.setError(error.localizedDescription)
            return nil
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

}
