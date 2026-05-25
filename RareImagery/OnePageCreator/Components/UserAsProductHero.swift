import SwiftUI

/// Hero block for OnePageCreator. Large PFP (120pt) with a subtle purple
/// glow ring, "You are the product" framing, and the user's display name.
///
/// Aligned with the principle:
///   "Make the user the product first — use their PFP as the hero asset."
struct UserAsProductHero: View {
    let pfpURL: URL?
    let displayName: String

    var body: some View {
        VStack(spacing: 14) {
            avatar
                .frame(width: 120, height: 120)
                .clipShape(Circle())
                .overlay(
                    Circle().stroke(AppColor.accent, lineWidth: 3)
                )
                .shadow(color: AppColor.accent.opacity(0.35), radius: 18, y: 0)

            VStack(spacing: 4) {
                Text("You are the product")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(AppColor.textPrimary)
                if !displayName.isEmpty {
                    Text(displayName)
                        .font(AppFont.callout)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    @ViewBuilder
    private var avatar: some View {
        if let url = pfpURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Circle()
            .fill(LinearGradient(
                colors: [AppColor.surface, AppColor.surfaceSecondary],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
            .overlay {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(AppColor.textSecondary)
            }
    }
}

#Preview {
    VStack {
        UserAsProductHero(pfpURL: nil, displayName: "Jordan Reyes")
        Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(AppColor.background)
    .preferredColorScheme(.dark)
}
