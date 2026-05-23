import SwiftUI
import RareImageryAPI

/// First screen a new user sees. Introduces Rare (the mascot —
/// "always your friend") and offers a single sign-in path through X
/// OAuth. The bloodhound is the brand's face: the welcome lets Rare
/// carry the warmth that stark typography alone can't.
///
/// Brand notes:
///   - Rare = the dog mascot. Voice is first-person, friendly.
///   - The logo lives at `Assets.xcassets/rareimagery-logo.imageset/`.
///     Until that asset is in place, this view falls back to an SF
///     Symbol so the layout renders. Replace the placeholder once
///     the PNG is dragged in — search this file for "TODO(logo)".
///   - CTA color is `AppColor.cta` (#FF6B00 orange) — onboarding
///     uses the warm CTA, not `AppColor.accent` (purple), which is
///     for in-app actions.
///
/// Wiring:
///   - `signInWithX` calls `AuthCoordinator.signInWithX(state:)`
///     which is the real PKCE flow in `Packages/RareImageryAPI`.
///     On success, `AuthSession.status` flips to `.signedIn`, and
///     the ContentView router moves to the next phase.
struct WelcomeView: View {
    @Environment(AppState.self) private var state
    @State private var isSigningIn = false
    @State private var coordinator = AuthCoordinator()

    var body: some View {
        ZStack {
            AppColor.background.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                // TODO(logo): drop the Rare bloodhound PNG into
                //   RareImagery/Assets.xcassets/rareimagery-logo.imageset/
                // (including a Contents.json with 1x/2x/3x variants),
                // then replace the SF Symbol below with:
                //   Image("rareimagery-logo")
                //     .resizable()
                //     .scaledToFit()
                //     .frame(width: 200, height: 200)
                Image(systemName: "pawprint.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 140, height: 140)
                    .foregroundStyle(AppColor.cta)

                VStack(spacing: 14) {
                    Text("Meet Rare")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(AppColor.textPrimary)

                    Text("Your friend in the merch business.\nShow Rare anything — he'll help you sell it.")
                        .font(.system(size: 17))
                        .foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 32)
                }

                Spacer()

                Button(action: { Task { await signIn() } }) {
                    HStack(spacing: 10) {
                        if isSigningIn {
                            ProgressView()
                                .tint(.black)
                        }
                        Text(isSigningIn ? "Connecting…" : "Sign in with X")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(isSigningIn ? AppColor.cta.opacity(0.5) : AppColor.cta)
                    .clipShape(Capsule())
                }
                .disabled(isSigningIn)
                .padding(.horizontal, 24)

                Text("@rareimagery is always your friend.")
                    .font(.footnote)
                    .foregroundStyle(AppColor.textSecondary.opacity(0.8))
                    .padding(.top, 4)

                if let error = state.session.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.top, 4)
                }

                Spacer().frame(height: 32)
            }
        }
    }

    private func signIn() async {
        guard !isSigningIn else { return }
        isSigningIn = true
        await coordinator.signInWithX(state: state)
        isSigningIn = false
    }
}

#Preview {
    WelcomeView()
        .environment(AppState())
        .preferredColorScheme(.dark)
}
