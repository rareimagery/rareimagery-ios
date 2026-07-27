import AuthenticationServices
import SwiftUI
import RareImageryAPI

/// Optional enrichment: link an X account to an existing Apple/Google creator profile.
struct LinkXAccountView: View {
    @Environment(AppState.self) private var state
    @State private var coordinator = AuthCoordinator()
    @State private var isLinking = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Link X")
                .font(AppFont.bodyText(17, .semibold))
                .foregroundStyle(AppColor.textPrimary)
            Text("Connect your X account for avatar, handle, and follower enrichment.")
                .font(AppFont.bodyText(14))
                .foregroundStyle(AppColor.textSecondary)

            if let message {
                Text(message)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.gold)
            }

            Button {
                Task { await linkX() }
            } label: {
                HStack {
                    if isLinking { ProgressView().tint(.white) }
                    Text(isLinking ? "Linking…" : "Link X account")
                        .font(AppFont.buttonLabel)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.black, in: RoundedRectangle(cornerRadius: 12))
            }
            .disabled(isLinking || !state.configuration.isXClientIDConfigured)
        }
        .padding(16)
        .background(AppColor.surface.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
    }

    private func linkX() async {
        isLinking = true
        defer { isLinking = false }
        if let handle = await coordinator.linkXAccount(state: state) {
            message = "Linked @\(handle) successfully."
        }
    }
}
