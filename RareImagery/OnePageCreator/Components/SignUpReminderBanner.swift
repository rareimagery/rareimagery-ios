import SwiftUI

/// Phase 3 soft sign-up reminder. Shown above the Create+Launch button
/// in OnePageCreator when the anonymous trial user has spent their 3
/// free vibe-photo merch-ideas calls.
///
/// Per the Phase 3 spec: this is a **soft** banner. The app keeps working
/// (the user can browse, change product type chips, refresh ideas — the
/// last one will 429 server-side but doesn't crash). The wall isn't here
/// — the wall is at the generation step, where the anonymous JWT 401s
/// against `/api/design-studio/generate` and the ViewModel intercepts
/// the tap to surface this same CTA in modal form.
///
/// Copy is value-forward: it names what the user UNLOCKS, not what they
/// give up. Aligns with the principle that converting trial users
/// happens at the dopamine moment ("I want to see this on a shirt"),
/// not by friction-flooding the discovery moment.
struct SignUpReminderBanner: View {
    let onConnectX: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(AppColor.accent)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text("Unlock real mockups + publish to your store")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.leading)

                Text("Connect X to spin your ideas into real shirts, hoodies, and caps your followers can buy.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onConnectX) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Connect X")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(AppColor.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(AppColor.accent.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppColor.accent.opacity(0.35), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }
}

#Preview {
    VStack {
        SignUpReminderBanner(onConnectX: {})
        Spacer()
    }
    .padding(.top, 24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(AppColor.background)
    .preferredColorScheme(.dark)
}
