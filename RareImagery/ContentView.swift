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
///   3. RETURNING user (or anyone who's tapped "Create first product" /
///      "Just explore" on the LivePreviewView) → CaptureFlowView (the main
///      app entry).
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
                NavigationStack {
                    CaptureFlowView()
                }
                .tint(AppColor.accent)
            }
        }
    }

    private func needsLegacyOnboarding(_ claims: MobileClaims) -> Bool {
        (claims.storeUuid ?? "").isEmpty || (claims.slug ?? "").isEmpty
    }

    private func handleLivePreviewAction(_ action: LivePreviewView.Action) {
        // Two parent-driven actions remain after the FirstProduct
        // wizard moved internal to LivePreviewView (via fullScreenCover):
        //
        //   - .tweakStore  → fires after the user dismisses TweakSheetView
        //                    (presented internally by LivePreviewView).
        //                    Semantically equivalent to "Just explore" —
        //                    they go to the main app.
        //   - .justExplore → user explicitly skipped the wizard. Route
        //                    to the main app.
        //
        // Both flip hasSeenLivePreview so we don't re-render the welcome
        // screen on next render tick. CaptureFlowView is the default
        // landing for both. If we later add a separate "browse / explore"
        // view, .justExplore would route there instead.
        //
        // Note: the previous .createFirstProduct case is gone — the
        // wizard's "Continue to Rare" CTA on Screen 3 flips
        // hasSeenLivePreview directly via FirstProductFlowView's
        // finishWizard() helper. We never round-trip back here for
        // that path.
        state.session.hasSeenLivePreview = true
    }
}
