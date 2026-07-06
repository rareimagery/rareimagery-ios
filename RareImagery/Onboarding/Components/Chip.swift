import SwiftUI

/// Capsule pill button used in the first-product wizard's setup step.
///
/// Two states: selected (filled with `AppColor.cta`, black text) and
/// unselected (filled with `AppColor.surface`, primary text, border).
/// Tap fires the action; the parent owns the truth and re-renders.
///
/// Shape constants intentionally match the chips inside `TweakSheetView`
/// so the visual vocabulary stays consistent across the onboarding flow.
struct Chip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(isSelected ? AppColor.cta : AppColor.surface, in: Capsule())
                .foregroundStyle(isSelected ? .black : AppColor.textPrimary)
                .overlay(
                    Capsule().stroke(
                        isSelected ? Color.clear : AppColor.border,
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    VStack(spacing: 12) {
        Chip(title: "Merch", isSelected: true, action: {})
        Chip(title: "Digital Products", isSelected: false, action: {})
        Chip(title: "Art / Prints", isSelected: false, action: {})
    }
    .padding(24)
    .background(AppColor.background)
    .preferredColorScheme(.dark)
}
