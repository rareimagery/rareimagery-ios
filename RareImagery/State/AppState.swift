import Foundation
import RareImageryAPI

/// Root composition container — wires up SPM services and exposes them to SwiftUI.
@MainActor
@Observable
final class AppState {
    let configuration: APIConfiguration
    let keychain: KeychainStore
    let client: APIClient
    let authManager: AuthManager
    let authRepository: AuthRepository
    let authService: AuthService
    let productRepository: ProductRepository
    let onboardingRepository: OnboardingRepository
    let circleRepository: CircleRepository
    let circleShareRepository: CircleShareRepository
    let designGenerationRepository: DesignGenerationRepository
    let anonymousAuthRepository: AnonymousAuthRepository
    let publishProductRepository: PublishProductRepository
    let videoUploadRepository: VideoUploadRepository
    let mediaUploadRepository: MediaUploadRepository
    let captureRepository: CaptureRepository
    let voiceTokenClient: VoiceTokenClient
    let storeDiscoveryRepository: StoreDiscoveryRepository
    let salesRepository: SalesRepository
    let session: AuthSession
    let capture: CaptureSession
    /// Finishes AuthManager → APIClient wiring started in `init`. Bootstrap
    /// awaits this so launch refresh uses the Drupal OAuth handler, not a
    /// racing fallback to the legacy BFF `/api/mobile/auth/refresh` route.
    /// Optional var (assigned last in `init`) because the Task closure
    /// captures `self`, which requires all stored properties initialized.
    private var authWiringTask: Task<Void, Never>?

    /// ponytail: stub-everything data layer for the value-first funnel phase
    /// (build the frontend now, connect the backend later). When true,
    /// `CaptureCoordinator` returns a mock valuation instead of calling the live
    /// `/api/vision/analyze`. Flipping this to false is the whole "connect the
    /// backend" switch — no view changes needed.
    /// Live since 2026-07-05: X_CLIENT_ID ships via Configuration/*.local.xcconfig
    /// and the BFF's anonymous /api/v1/vision/value + draft claim are deployed
    /// locally. Flip back to true for backend-free UI demos.
    let useMocks = false

    init() {
        self.configuration = APIConfiguration.fromBundle
        let keychain = KeychainStore()
        self.keychain = keychain
        let client = APIClient(configuration: configuration, keychain: keychain)
        self.client = client
        let authURLSession = URLSession(
            configuration: {
                let config = URLSessionConfiguration.default
                config.timeoutIntervalForRequest = 20
                config.timeoutIntervalForResource = 30
                config.waitsForConnectivity = false
                return config
            }()
        )
        let authManager = AuthManager(
            configuration: configuration,
            keychain: keychain,
            urlSession: authURLSession
        )
        self.authManager = authManager
        self.authRepository = AuthRepository(client: client)
        self.authService = AuthService(configuration: configuration, repository: authRepository, client: client)
        self.productRepository = ProductRepository(client: client)
        self.onboardingRepository = OnboardingRepository(client: client)
        self.circleRepository = CircleRepository(client: client)
        self.circleShareRepository = CircleShareRepository(client: client)
        self.designGenerationRepository = DesignGenerationRepository(client: client)
        self.anonymousAuthRepository = AnonymousAuthRepository(client: client)
        self.publishProductRepository = PublishProductRepository(client: client)
        self.videoUploadRepository = VideoUploadRepository(client: client)
        self.mediaUploadRepository = MediaUploadRepository(client: client)
        self.captureRepository = CaptureRepository(client: client)
        self.voiceTokenClient = VoiceTokenClient(client: client)
        self.storeDiscoveryRepository = StoreDiscoveryRepository(client: client)
        self.salesRepository = SalesRepository(client: client)
        self.session = AuthSession()

        // Phase 4.2 — Analytics dispatch swap. Configure ONCE here so
        // every Analytics.record(_:) call from anywhere in the app
        // (AppState bootstrap, ViewModels, View observers) reaches
        // both the console log AND the BFF /api/v1/telemetry/event
        // endpoint without per-call ceremony.
        //
        // sessionId is a fresh UUID per app launch — groups events
        // from one user session in the Drupal telemetry_event table
        // so cohort + funnel queries can group by `session_id`.
        Analytics.configure(client: client, sessionId: UUID().uuidString.lowercased())
        self.capture = CaptureSession()

        authWiringTask = Task { [weak self] in
            guard let self else { return }
            await self.authManager.install(on: self.client)
            await self.client.setAuthEventHandlers(AuthEventHandlers(
                onTokensRefreshed: { [weak self] tokens in
                    await MainActor.run {
                        guard let self else { return }
                        self.session.applyOAuthTokens(
                            accessToken: tokens.accessToken,
                            expiresAt: tokens.accessTokenExpiresAt
                        )
                    }
                },
                onSessionInvalidated: { [weak self] in
                    let state = await MainActor.run { self }
                    guard let state else { return }
                    await state.handleSessionInvalidated()
                }
            ))
        }
    }

    private func ensureAuthWiringReady() async {
        await authWiringTask?.value
    }

    private func logAuthConfig() {
        let logger = APILogger(category: "AppState")
        let prefix = String(configuration.xClientID.prefix(8))
        let mode = configuration.isOAuthClientConfigured ? "broker" : "legacy"
        let host = configuration.baseURL.host ?? "?"
        logger.info(
            "auth config: mode=\(mode) xClient=\(prefix)… apiHost=\(host) xConfigured=\(configuration.isXClientIDConfigured) oauthConfigured=\(configuration.isOAuthClientConfigured)"
        )
    }

    private func handleSessionInvalidated() async {
        await authManager.signOut()
        try? await authService.signOut()
        session.setSignedOut(error: "Session expired. Please sign in again.")
        capture.reset()
    }

    /// Called once on app launch. Resolution order (Phase 3):
    ///   1. Production session — `.refreshToken` exists AND `.accessToken`
    ///      decodes as `MobileClaims` → `.signedIn(...)`
    ///   2. Existing anonymous trial — `.anonymousDeviceId` exists AND
    ///      `.accessToken` is non-expired → `.anonymous(...)`
    ///   3. Brand new device OR expired trial — mint a fresh anonymous
    ///      JWT, persist it, → `.anonymous(...)`
    ///   4. All paths fail (e.g. BFF down on first launch) → `.signedOut`
    ///      with error message
    ///
    /// Why discriminate on `.refreshToken` presence (step 1): anonymous
    /// tokens are issued WITHOUT a refresh token. Their absence is the
    /// cleanest signal that whatever's in `.accessToken` is the trial JWT,
    /// not a production one — no need to decode the JWT itself to find out.
    func bootstrap() async {
        defer {
            if case .checking = session.status {
                session.setSignedOut(
                    error: "Couldn't start app session. Check your connection and try again."
                )
            }
        }

        #if DEBUG
        // ponytail: useMocks means "no backend" — mint the anonymous session
        // locally so the value-first funnel is reachable offline. Real mint
        // (bootstrapAnonymous) runs the moment useMocks flips to false.
        if useMocks {
            let claims = AnonymousClaims(
                deviceId: "mock-device",
                exp: Int(Date().timeIntervalSince1970) + 86_400
            )
            session.setAnonymous(claims: claims, freeUsesRemaining: AuthSession.anonymousFreeUsesCap)
            return
        }
        #endif

        await ensureAuthWiringReady()
        logAuthConfig()

        if await tryProductionSession() { return }
        if await tryExistingAnonymousSession() { return }
        await bootstrapAnonymous()
    }

    private func tryProductionSession() async -> Bool {
        guard let refresh = try? await keychain.get(.refreshToken), !refresh.isEmpty else {
            return false
        }

        // Production user — never downgrade to anonymous on this path.
        do {
            _ = await authManager.restoreFromKeychain()

            let access = try await keychain.get(.accessToken)
            let needsRefresh: Bool
            if let access, let claims = Self.claims(from: access) {
                needsRefresh = claims.shouldRefresh()
            } else if let expiryString = try? await keychain.get(.accessTokenExpiry),
                      let expiry = ISO8601DateFormatter().date(from: expiryString) {
                needsRefresh = expiry.timeIntervalSinceNow <= 60
            } else {
                needsRefresh = true
            }

            if needsRefresh {
                let refreshed = try await refreshProductionTokens()
                session.applyOAuthTokens(
                    accessToken: refreshed.accessToken,
                    expiresAt: refreshed.expiresAt
                )
            } else if let access {
                session.applyOAuthTokens(accessToken: access, expiresAt: nil)
            } else {
                let refreshed = try await refreshProductionTokens()
                session.applyOAuthTokens(
                    accessToken: refreshed.accessToken,
                    expiresAt: refreshed.expiresAt
                )
            }
            return true
        } catch {
            try? await authManager.signOut()
            try? await authService.signOut()
            session.setSignedOut(error: "Session expired. Please sign in again.")
            return true
        }
    }

    private func refreshProductionTokens() async throws -> (accessToken: String, expiresAt: Date?) {
        if configuration.isOAuthClientConfigured {
            let set = try await authManager.refreshTokens()
            return (set.accessToken, set.expiresAt)
        }
        let tokens = try await client.refreshTokens()
        return (tokens.accessToken, tokens.accessTokenExpiresAt)
    }

    private static func claims(from accessToken: String) -> MobileClaims? {
        if let claims = try? JWTDecoder.decode(accessToken) {
            return claims
        }
        if let claims = try? JWTDecoder.decodePayload(accessToken), !claims.isExpired {
            return claims
        }
        return nil
    }

    private func tryExistingAnonymousSession() async -> Bool {
        do {
            guard let deviceId = try await keychain.get(.anonymousDeviceId), !deviceId.isEmpty,
                  let _ = try await keychain.get(.accessToken),
                  let expiryString = try await keychain.get(.accessTokenExpiry),
                  let expiry = ISO8601DateFormatter().date(from: expiryString),
                  expiry > Date() else {
                return false
            }
            let claims = AnonymousClaims(deviceId: deviceId, exp: Int(expiry.timeIntervalSince1970))
            let used = await loadAnonymousFreeUsesUsed()
            let remaining = max(0, AuthSession.anonymousFreeUsesCap - used)
            session.setAnonymous(claims: claims, freeUsesRemaining: remaining)
            return true
        } catch {
            return false
        }
    }

    /// Mint a fresh anonymous JWT for this device. Reuses an existing
    /// `.anonymousDeviceId` when present (so the BFF rate-limit bucket +
    /// the per-device free-uses counter stay stable across token refresh).
    /// Generates a new UUID on first launch.
    private func bootstrapAnonymous() async {
        let deviceId: String
        do {
            if let existing = try await keychain.get(.anonymousDeviceId), !existing.isEmpty {
                deviceId = existing
            } else {
                deviceId = UUID().uuidString.lowercased()
                try await keychain.set(deviceId, for: .anonymousDeviceId)
            }
        } catch {
            session.setSignedOut(error: "Couldn't prepare trial session: \(error.localizedDescription)")
            return
        }

        do {
            let response = try await anonymousAuthRepository.requestToken(deviceId: deviceId)
            try await keychain.set(response.accessToken, for: .accessToken)
            let expiryString = ISO8601DateFormatter().string(from: response.expiresAt)
            try await keychain.set(expiryString, for: .accessTokenExpiry)
            // Anonymous has no refresh path — clear any stale prod refresh
            // token so `tryProductionSession()` won't false-positive next
            // launch on a token that was already invalidated.
            try? await keychain.remove(.refreshToken)

            let claims = AnonymousClaims(
                deviceId: response.deviceId,
                exp: Int(response.expiresAt.timeIntervalSince1970)
            )
            let used = await loadAnonymousFreeUsesUsed()
            let remaining = max(0, AuthSession.anonymousFreeUsesCap - used)
            session.setAnonymous(claims: claims, freeUsesRemaining: remaining)
            // Phase 3.3 — top-of-funnel event. Fired once per successful
            // mint (which is at most once per app launch). When a real
            // analytics service lands, this is automatically delivered
            // without touching this code.
            Analytics.record(.anonymousSessionStarted(deviceId: response.deviceId))
        } catch {
            session.setSignedOut(error: "Couldn't start free trial: \(error.localizedDescription)")
        }
    }

    private func loadAnonymousFreeUsesUsed() async -> Int {
        do {
            if let raw = try await keychain.get(.anonymousFreeUsesUsed),
               let n = Int(raw) {
                return n
            }
        } catch {
            // fall through to 0
        }
        return 0
    }

    /// Phase 3 — call after a successful anonymous merch-ideas response.
    /// Increments the persisted "uses spent" counter AND decrements the
    /// session's `freeUsesRemaining`. No-op when not in anonymous tier so
    /// it's safe for the OnePageCreatorViewModel to call uniformly.
    func recordAnonymousFreeUseSpent() async {
        guard session.isAnonymous else { return }
        let current = await loadAnonymousFreeUsesUsed()
        let new = current + 1
        try? await keychain.set(String(new), for: .anonymousFreeUsesUsed)
        session.decrementFreeUses()
    }

    func signOut() async {
        await authManager.signOut()
        do { try await authService.signOut() } catch { session.setError("Sign-out failed: \(error)") }
        // Phase 3: on explicit sign-out, also clear the anonymous trial
        // state. Returning to anonymous after a deliberate sign-out feels
        // dishonest — re-entry should show the sign-in flow, not the trial.
        try? await keychain.clearAnonymousState()
        session.setSignedOut()
        capture.reset()
    }

    #if DEBUG
    /// Bypass real OAuth for local testing without X or the BFF.
    /// Lands in the main app shell with a synthetic signed-in session.
    func debugSimulateSignIn() {
        let now = Int(Date().timeIntervalSince1970)
        let claims = MobileClaims(
            sub: "debug-user",
            storeUuid: "debug-store",
            slug: "debug",
            handle: "debug_user",
            role: "CREATOR",
            aud: MobileClaims.expectedAudience,
            exp: now + 3600,
            iat: now
        )
        session.status = .signedIn(claims)
        session.lastError = nil
        session.hasSeenLivePreview = true
        session.hasSeenFunnel = true
    }
    #endif
}
