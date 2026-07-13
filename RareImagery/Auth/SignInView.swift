import SwiftUI
import RareImageryAPI

struct SignInView: View {
    @Environment(AppState.self) private var state
    @State private var coordinator = AuthCoordinator()
    @State private var isAuthenticating = false

    private var usesDrupalOAuth: Bool {
        state.configuration.isOAuthClientConfigured
    }

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 64, weight: .bold))
                    .foregroundStyle(AppColor.accent)
                Text("RareImagery")
                    .font(AppFont.largeTitle)
                    .foregroundStyle(AppColor.textPrimary)
                Text("Capture. Co-sign. Sell.")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textSecondary)
            }

            Spacer()

            if let error = state.session.lastError {
                Text(error)
                    .font(AppFont.caption)
                    .foregroundStyle(.red.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            VStack(spacing: 12) {
                Button {
                    Task {
                        isAuthenticating = true
                        if usesDrupalOAuth {
                            await coordinator.signInWithDrupal(state: state)
                        } else {
                            await coordinator.signInWithX(state: state)
                        }
                        isAuthenticating = false
                    }
                } label: {
                    HStack(spacing: 10) {
                        if isAuthenticating {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: usesDrupalOAuth ? "person.crop.circle.badge.checkmark" : "x.square.fill")
                                .font(.system(size: 20, weight: .semibold))
                        }
                        Text(primaryButtonTitle)
                            .font(AppFont.buttonLabel)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(AppColor.border, lineWidth: 1)
                    )
                }
                .disabled(isAuthenticating)
                .padding(.horizontal, 24)

                Text("By continuing you agree to RareImagery's terms.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)

                #if DEBUG
                if usesDrupalOAuth {
                    Button {
                        Task {
                            isAuthenticating = true
                            await coordinator.signInWithX(state: state)
                            isAuthenticating = false
                        }
                    } label: {
                        Text("Continue with X (legacy BFF)")
                            .font(AppFont.bodyText(14))
                            .foregroundStyle(AppColor.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .disabled(isAuthenticating)
                }

                Button {
                    state.debugSimulateSignIn()
                } label: {
                    Text("Skip sign-in (testing)")
                        .font(AppFont.bodyText(14))
                        .foregroundStyle(AppColor.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .padding(.top, 8)
                #endif
            }

            Spacer().frame(height: 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.background)
        .ignoresSafeArea()
    }

    private var primaryButtonTitle: String {
        if isAuthenticating { return "Signing in…" }
        return usesDrupalOAuth ? "Sign in" : "Continue with X"
    }
}
