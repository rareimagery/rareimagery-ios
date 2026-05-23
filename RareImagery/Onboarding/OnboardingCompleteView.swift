import SwiftUI

/// Tasteful onboarding closer. User has signed in, granted camera, and
/// (optionally) completed the wizard. Confirms everything's ready and
/// hands off to the main app. Single CTA — keep it warm, keep it short.
///
/// Voice: still Rare-led. The user has just shared their identity with
/// the app; the close-out reciprocates with friendliness, not a feature
/// list.
struct OnboardingCompleteView: View {
    let onContinue: () -> Void

    @State private var iconScale: CGFloat = 0.7
    @State private var iconOpacity: Double = 0

    var body: some View {
        ZStack {
            AppColor.background.ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 88, weight: .light))
                    .foregroundStyle(AppColor.cta)
                    .scaleEffect(iconScale)
                    .opacity(iconOpacity)
                    .onAppear {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                            iconScale = 1.0
                            iconOpacity = 1.0
                        }
                    }

                VStack(spacing: 14) {
                    Text("You're all set")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(AppColor.textPrimary)

                    Text("Rare's ready when you are. Tap to start finding things worth selling.")
                        .font(.system(size: 17))
                        .foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 32)
                }

                Spacer()

                Button(action: onContinue) {
                    Text("Start with Rare")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(AppColor.cta)
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 24)

                Spacer().frame(height: 32)
            }
        }
    }
}

#Preview {
    OnboardingCompleteView(onContinue: {})
        .preferredColorScheme(.dark)
}
