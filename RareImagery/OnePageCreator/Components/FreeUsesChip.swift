import SwiftUI

/// Phase 3.2 — visible counter for the anonymous trial budget.
///
/// Shown directly under the UserAsProductHero when the user is in
/// anonymous tier AND has > 0 free vibe analyses remaining. Hidden when:
///   - signed in (counter doesn't apply)
///   - 0 remaining (SignUpReminderBanner takes over near the CTA)
///
/// Purpose: make the generous free tier *visible* from use #1 instead of
/// surprising the user when the banner appears at use #4. Pairs with the
/// banner — they're two halves of the same trial UX (before/after threshold).
///
/// Copy tone matches the "fun and free" principle — "3 free vibe analyses"
/// reads as a gift, not a constraint. The shorter "2 / 1 free left"
/// variants kick in once the user has spent at least one, signaling
/// movement toward the threshold without scarcity-shaming.
struct FreeUsesChip: View {
    let remaining: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .semibold))
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
        }
        .foregroundStyle(AppColor.accent)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(AppColor.accent.opacity(0.12))
        )
        .overlay(
            Capsule().stroke(AppColor.accent.opacity(0.30), lineWidth: 1)
        )
        .accessibilityLabel("\(remaining) free vibe analyses remaining")
    }

    private var label: String {
        switch remaining {
        case 3: return "3 free vibe analyses"
        case 2: return "2 free left"
        case 1: return "1 free left"
        default: return "\(remaining) free left"  // defensive — never seen in practice
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        Spacer()
        FreeUsesChip(remaining: 3)
        FreeUsesChip(remaining: 2)
        FreeUsesChip(remaining: 1)
        Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(AppColor.background)
    .preferredColorScheme(.dark)
}
