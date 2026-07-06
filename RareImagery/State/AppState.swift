import Foundation
import RareImageryAPI

/// Root composition container — wires up SPM services and exposes them to SwiftUI.
@MainActor
@Observable
final class AppState {
    let configuration: APIConfiguration
    let keychain: KeychainStore
    let client: APIClient
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
    let session: AuthSession
    let capture: CaptureSession

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
        if await tryProductionSession() { return }
        if await tryExistingAnonymousSession() { return }
        await bootstrapAnonymous()
    }

    private func tryProductionSession() async -> Bool {
        do {
            if let refresh = try await keychain.get(.refreshToken), !refresh.isEmpty,
               let access = try await keychain.get(.accessToken) {
                let claims = try JWTDecoder.decode(access)
                session.status = .signedIn(claims)
                return true
            }
        } catch {
            // fall through — production session unavailable, try anonymous
        }
        return false
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
        do { try await authService.signOut() } catch { session.setError("Sign-out failed: \(error)") }
        // Phase 3: on explicit sign-out, also clear the anonymous trial
        // state. Returning to anonymous after a deliberate sign-out feels
        // dishonest — re-entry should show the sign-in flow, not the trial.
        try? await keychain.clearAnonymousState()
        session.setSignedOut()
        capture.reset()
    }

    #if DEBUG
    /// Bypass real OAuth for capture-flow testing without a backend.
    /// Synthesizes a fake MobileClaims envelope and flips session to signedIn.
    func debugSimulateSignIn() {
        let now = Int(Date().timeIntervalSince1970)
        let claims = MobileClaims(
            sub: "debug-user",
            storeUuid: "debug-store",
            slug: "debug",
            handle: "debug_user",
            role: "x_creator",
            aud: MobileClaims.expectedAudience,
            exp: now + 3600,
            iat: now
        )
        session.status = .signedIn(claims)
    }
    #endif
}
