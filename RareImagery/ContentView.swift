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
            if needsLegacyOnboarding(claims, creator: state.session.creator) {
                // Defensive fallback — shouldn't fire because CreatorProvisioner
                // mints storeUuid/slug atomically at sign-in. If the wire ever
                // decouples, the old wizard catches it.
                OnboardingView(keychain: state.keychain)
            } else {
                // Straight to the app. The old "You're live / Create your
                // first product" (LivePreviewView) interstitial routed into
                // the t-shirt/merch generator and has been removed — signed-in
                // users land on Home, where "Add a product" is the primary
                // (video → Grok) create action.
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

    private func needsLegacyOnboarding(
        _ claims: MobileClaims,
        creator: AuthTokenResponse.Creator?
    ) -> Bool {
        if let creator,
           !(creator.storeUuid ?? "").isEmpty,
           !(creator.slug ?? "").isEmpty {
            return false
        }
        return (claims.storeUuid ?? "").isEmpty || (claims.slug ?? "").isEmpty
    }

}
