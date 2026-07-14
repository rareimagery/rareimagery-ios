import SwiftUI
import RareImageryAPI

/// Sign-in / account-creation screen — redesigned 2026-07-13.
///
/// Design: vault gradient + foil gold per the 2026-06-25 brand refresh
/// (`Theme/Colors.swift`). One screen, X auth primary. "Continue with X"
/// covers both login and account creation — the BFF provisions the creator
/// on first OAuth round-trip, so there is deliberately no separate
/// "create account" path.
///
/// Error handling: `AuthSession.lastError` strings are mapped to friendly
/// copy in `friendlyError`. The anonymous-trial bootstrap failure
/// ("Couldn't start free trial…", i.e. the BFF was unreachable or the
/// mint endpoint 404'd) is retryable in place via `state.bootstrap()` —
/// previously the raw error rendered as a dead-end red string.
struct SignInView: View {
    @Environment(AppState.self) private var state
    @State private var coordinator = AuthCoordinator()
    @State private var isAuthenticating = false
    @State private var isRetryingTrial = false

    private var usesDrupalOAuth: Bool {
        state.configuration.isOAuthClientConfigured
    }

    var body: some View {
        ZStack {
            AppColor.vaultGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 56)

                header

                valueProps
                    .padding(.top, 36)

                Spacer()

                VStack(spacing: 14) {
                    if let error = friendlyError {
                        errorCard(error)
                    }

                    primaryButton

                    Text("New here? Continuing with X creates your account.")
                        .font(AppFont.bodyText(14))
                        .foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.center)

                    Text("By continuing you agree to RareImagery's terms.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary.opacity(0.7))

                    #if DEBUG
                    debugControls
                    #endif
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 54, weight: .bold))
                .foregroundStyle(AppColor.foil)
                .shadow(color: AppColor.gold.opacity(0.35), radius: 18, y: 4)

            (Text("RareImagery").foregroundStyle(AppColor.textPrimary)
                + Text(".").foregroundStyle(AppColor.gold))
                .font(AppFont.display(38, .bold))

            Text("CAPTURE · CO-SIGN · SELL")
                .font(AppFont.mono(13, .medium))
                .tracking(3)
                .foregroundStyle(AppColor.textSecondary)
        }
    }

    // MARK: - Value props

    private var valueProps: some View {
        VStack(alignment: .leading, spacing: 14) {
            valueRow(icon: "viewfinder",
                     text: "Capture anything rare — photos, video, your voice")
            valueRow(icon: "sparkles",
                     text: "AI identifies and values it in seconds")
            valueRow(icon: "storefront",
                     text: "Publish straight to your own storefront")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.surface.opacity(0.55), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppColor.border, lineWidth: 1)
        )
        .padding(.horizontal, 24)
    }

    private func valueRow(icon: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppColor.gold)
                .frame(width: 26)
            Text(text)
                .font(AppFont.bodyText(15))
                .foregroundStyle(AppColor.textPrimary.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Primary action

    private var primaryButton: some View {
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
                    Image(systemName: usesDrupalOAuth
                          ? "person.crop.circle.badge.checkmark"
                          : "x.square.fill")
                        .font(.system(size: 20, weight: .semibold))
                }
                Text(primaryButtonTitle)
                    .font(AppFont.buttonLabel)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(AppColor.borderGold, lineWidth: 1)
            )
        }
        .disabled(isAuthenticating)
    }

    private var primaryButtonTitle: String {
        if isAuthenticating { return "Signing in…" }
        return usesDrupalOAuth ? "Sign in" : "Continue with X"
    }

    // MARK: - Errors

    private struct FriendlyError {
        let icon: String
        let message: String
        /// True only for the anonymous-trial bootstrap failure — the one
        /// case where retrying `state.bootstrap()` (not re-auth) is the fix.
        let canRetryTrial: Bool
    }

    private var friendlyError: FriendlyError? {
        guard let raw = state.session.lastError, !raw.isEmpty else { return nil }

        if raw.hasPrefix("Couldn't start free trial")
            || raw.hasPrefix("Couldn't prepare trial session") {
            return FriendlyError(
                icon: "wifi.exclamationmark",
                message: "We couldn't reach RareImagery. Check your connection and try again.",
                canRetryTrial: true
            )
        }
        if raw.localizedCaseInsensitiveContains("client id")
            || raw.localizedCaseInsensitiveContains("configuration") {
            return FriendlyError(
                icon: "gearshape.fill",
                message: "Sign-in isn't set up in this build. Please update to the latest version.",
                canRetryTrial: false
            )
        }
        if raw.localizedCaseInsensitiveContains("expired") {
            return FriendlyError(
                icon: "clock.arrow.circlepath",
                message: "You were signed out. Sign in again to keep selling.",
                canRetryTrial: false
            )
        }
        return FriendlyError(
            icon: "exclamationmark.triangle.fill",
            message: raw,
            canRetryTrial: false
        )
    }

    private func errorCard(_ error: FriendlyError) -> some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: error.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColor.gold)
                Text(error.message)
                    .font(AppFont.bodyText(14))
                    .foregroundStyle(AppColor.textPrimary.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if error.canRetryTrial {
                Button {
                    Task {
                        isRetryingTrial = true
                        await state.bootstrap()
                        isRetryingTrial = false
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isRetryingTrial {
                            ProgressView()
                                .tint(AppColor.gold)
                                .controlSize(.small)
                        }
                        Text(isRetryingTrial ? "Retrying…" : "Try again")
                            .font(AppFont.bodyText(15, .semibold))
                    }
                    .foregroundStyle(AppColor.gold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .disabled(isRetryingTrial)
            }
        }
        .padding(14)
        .background(AppColor.surface.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppColor.borderGold, lineWidth: 1)
        )
    }

    // MARK: - Debug

    #if DEBUG
    @ViewBuilder
    private var debugControls: some View {
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
                .padding(.vertical, 8)
        }
    }
    #endif
}
