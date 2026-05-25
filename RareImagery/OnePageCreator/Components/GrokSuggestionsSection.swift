import SwiftUI
import RareImageryAPI

/// Section that renders the 3-5 Grok-generated merch concepts as
/// vertically-stacked cards. Each tap selects the concept and triggers
/// visual generation (via the parent ViewModel).
///
/// Skeleton state is shown when `isLoading`; empty state when ideas are
/// missing despite finishing load.
struct GrokSuggestionsSection: View {
    let ideas: [MerchIdeaDraft]
    let isLoading: Bool
    let selectedIdea: MerchIdeaDraft?
    let onSelect: (MerchIdeaDraft) -> Void
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Ideas just for you")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                Spacer()
                Button {
                    onRefresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColor.accent)
                }
                .accessibilityLabel("Refresh ideas")
            }
            .padding(.horizontal, 16)

            if isLoading && ideas.isEmpty {
                skeleton
            } else if ideas.isEmpty {
                empty
            } else {
                VStack(spacing: 10) {
                    ForEach(ideas) { idea in
                        IdeaCard(
                            idea: idea,
                            isSelected: idea.id == selectedIdea?.id,
                            onTap: { onSelect(idea) }
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var skeleton: some View {
        VStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 14)
                    .fill(AppColor.surface)
                    .frame(height: 78)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(AppColor.border, lineWidth: 1)
                    )
                    .redacted(reason: .placeholder)
            }
        }
        .padding(.horizontal, 16)
    }

    private var empty: some View {
        Text("Tap refresh to load merch ideas.")
            .font(AppFont.caption)
            .foregroundStyle(AppColor.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
    }
}

private struct IdeaCard: View {
    let idea: MerchIdeaDraft
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AppColor.accent.opacity(0.18))
                        .frame(width: 44, height: 44)
                    Image(systemName: "sparkles")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppColor.accent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(idea.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColor.textPrimary)
                        .multilineTextAlignment(.leading)
                    if !idea.description.isEmpty {
                        Text(idea.description)
                            .font(.system(size: 13))
                            .foregroundStyle(AppColor.textSecondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                    }
                    HStack(spacing: 6) {
                        Text(idea.category.displayName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppColor.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(AppColor.surfaceSecondary))
                        if let price = idea.estimatedPrice.display {
                            Text(price)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(AppColor.textSecondary)
                        }
                    }
                    .padding(.top, 2)
                }

                Spacer(minLength: 4)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "chevron.right")
                    .font(.system(size: isSelected ? 20 : 14, weight: .semibold))
                    .foregroundStyle(isSelected ? AppColor.accent : AppColor.textSecondary)
                    .padding(.top, 4)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(AppColor.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? AppColor.accent : AppColor.border, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}
