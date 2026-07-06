import SwiftUI

/// Generic card wrapping a question title + arbitrary content (typically
/// a chip group). Used by `FirstProductSetupView` to lay out the two
/// onboarding questions ("What kind of products?" / "What's your main vibe?").
///
/// Title style mirrors the uppercase-tracked field labels in
/// `QuickProductView` so the visual rhythm stays consistent across the
/// onboarding + product-creation surfaces.
struct QuestionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColor.textSecondary)
                .textCase(.uppercase)
                .tracking(0.6)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppColor.border, lineWidth: 1)
        )
    }
}

#Preview {
    VStack(spacing: 16) {
        QuestionCard("What kind of products do you want to sell most?") {
            HStack(spacing: 8) {
                Chip(title: "Merch", isSelected: true, action: {})
                Chip(title: "Digital", isSelected: false, action: {})
            }
        }

        QuestionCard("What's your main vibe or style?") {
            HStack(spacing: 8) {
                Chip(title: "Streetwear", isSelected: false, action: {})
                Chip(title: "Minimal", isSelected: true, action: {})
            }
        }
    }
    .padding(20)
    .background(AppColor.background)
    .preferredColorScheme(.dark)
}
