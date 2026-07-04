import SwiftUI
import RareImageryAPI

/// Top-level router. Three signed-in destinations:
///
///   1. NEW user (no storeUuid/slug — defensive guard, shouldn't fire in
///      practice since CreatorProvisioner mints both atomically at sign-in.
///      Kept per PR #1's defensive-gate decision.)
///      → OnboardingView (the legacy 4-step wizard; remains as a fallback)
///
///   2. RECENTLY signed-in user (storeUuid + slug present, hasn't dismissed
///      the live-preview screen yet) → LivePreviewView (the "You're live"
///      screen — the new onboarding pattern per the 2026-05-23 redesign).
///
///   3. RETURNING user (or anyone who's finished OnePageCreator /
///      tapped "Just explore" on LivePreviewView) → MainTabView.
///
/// The transition from state #2 → #3 is local-only: a flag on AuthSession
/// flips once the user dismisses the LivePreviewView. No round-trip to
/// the server. Sign-out resets the flag so the next sign-in re-shows
/// the welcome screen.
struct ContentView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        switch state.session.status {
        case .checking:
            ProgressView()
                .tint(AppColor.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppColor.background)
                .ignoresSafeArea()

        case .signedOut:
            SignInView()

        case .signedIn(let claims):
            if needsLegacyOnboarding(claims) {
                // Defensive fallback — shouldn't fire because CreatorProvisioner
                // mints storeUuid/slug atomically at sign-in. If the wire ever
                // decouples, the old wizard catches it.
                OnboardingView(keychain: state.keychain)
            } else if !state.session.hasSeenLivePreview {
                // The "You're live" screen — first thing a freshly-signed-in
                // user sees. Three actions decide what comes next.
                LivePreviewView(onAction: handleLivePreviewAction)
            } else {
                MainTabView()
            }

        case .anonymous:
            // Value-first video funnel on first launch; skip lands in MainTabView.
            // Trial-exhausted users go straight to the shell (per-screen gating).
            // Burst-capture / OnePageCreator wiring remains separate (XTOOLS §6).
            if !state.session.hasSeenFunnel, !state.session.trialExhausted {
                VideoSubmissionFunnelView(onExit: { state.session.hasSeenFunnel = true })
            } else {
                MainTabView()
            }
        }
    }

    private func needsLegacyOnboarding(_ claims: MobileClaims) -> Bool {
        (claims.storeUuid ?? "").isEmpty || (claims.slug ?? "").isEmpty
    }

    private func handleLivePreviewAction(_ action: LivePreviewView.Action) {
        // Parent-driven actions from LivePreviewView. OnePageCreator's
        // finish path flips hasSeenLivePreview inside OnePageCreatorHostView.
        state.session.hasSeenLivePreview = true
    }
}
