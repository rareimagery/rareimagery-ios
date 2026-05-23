import SwiftUI
import RareImageryAPI

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
            // Signed in but the server hasn't issued storeUuid/slug yet → onboarding.
            // (Once BFF adds a `needsOnboarding` JWT claim per the agent's note,
            // we can read that directly instead of inferring from missing fields.)
            if needsOnboarding(claims) {
                OnboardingView(keychain: state.keychain)
            } else {
                NavigationStack {
                    CaptureFlowView()
                }
                .tint(AppColor.accent)
            }
        }
    }

    private func needsOnboarding(_ claims: MobileClaims) -> Bool {
        (claims.storeUuid ?? "").isEmpty || (claims.slug ?? "").isEmpty
    }
}
