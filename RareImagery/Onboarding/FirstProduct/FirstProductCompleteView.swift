import SwiftUI
import RareImageryAPI

/// Screen 3 of the first-product wizard. Confirms the draft was
/// created, offers an X share (native iOS share sheet, NOT a custom
/// X API call), and a "Continue to Rare" CTA that drops the user
/// into the main app.
///
/// Naming note: this is **`FirstProductCompleteView`**, distinct from
/// PR #1's `OnboardingCompleteView` (which closes out the sign-in +
/// permissions phase). Both exist; they're sequenced — sign-in's
/// closer fires on first launch, this one fires once per
/// first-product flow.
///
/// Terms / Privacy live as inline Links, not a checkbox. Continuing
/// past this screen is treated as agreement (matching the web flow's
/// "by continuing, you agree" pattern post-PR #20).
struct FirstProductCompleteView: View {
    @Environment(AppState.self) private var state
    @Bindable var viewModel: FirstProductViewModel

    /// Closure injected by `FirstProductFlowView`. Flips
    /// `state.session.hasSeenLivePreview = true` AND dismisses the
    /// fullScreenCover — both happen together so ContentView's next
    /// render lands on the main app.
    let onFinish: () -> Void

    @State private var iconScale: CGFloat = 0.7
    @State private var iconOpacity: Double = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer().frame(height: 8)

                checkmarkBadge
                    .padding(.top, 12)

                headerCopy

                if let draft = viewModel.createdDraft {
                    draftSummary(for: draft)
                }

                shareCard

                Spacer().frame(height: 12)

                continueButton

                termsCopy

                Spacer().frame(height: 24)
            }
            .padding(.horizontal, 24)
        }
        .background(AppColor.background)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                iconScale = 1.0
                iconOpacity = 1.0
            }
        }
    }

    // MARK: - Sections

    private var checkmarkBadge: some View {
        Image(systemName: "checkmark.seal.fill")
            .font(.system(size: 72, weight: .light))
            .foregroundStyle(AppColor.cta)
            .scaleEffect(iconScale)
            .opacity(iconOpacity)
    }

    private var headerCopy: some View {
        VStack(spacing: 10) {
            Text("Almost done!")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)

            Text("Share your store with your followers — that's where the first sales come from.")
                .font(.system(size: 15))
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 12)
        }
    }

    private func draftSummary(for draft: ProductDraft) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your first product")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColor.textSecondary)
                .textCase(.uppercase)
                .tracking(0.6)
            Text(draft.title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.leading)
            if let priceDisplay = draft.priceDisplay {
                Text(priceDisplay)
                    .font(.system(size: 14))
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppColor.border, lineWidth: 1)
        )
    }

    private var shareCard: some View {
        VStack(spacing: 12) {
            Text(storefrontURL.absoluteString)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(AppColor.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(AppColor.background, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppColor.border, lineWidth: 1)
                )

            ShareLink(
                item: storefrontURL,
                message: Text(shareMessage)
            ) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Share on X")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(AppColor.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(AppColor.surface)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(AppColor.border, lineWidth: 1))
            }
        }
    }

    private var continueButton: some View {
        Button(action: onFinish) {
            Text("Continue to Rare")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(AppColor.cta)
                .clipShape(Capsule())
        }
    }

    private var termsCopy: some View {
        // Terms + Privacy as inline Links, not a checkbox. Tapping the
        // Continue button is the implicit agreement — matches the web
        // flow's "by continuing, you agree" pattern post-PR #20.
        Text("By continuing, you agree to the ")
            .font(.system(size: 11))
            .foregroundStyle(AppColor.textSecondary)
        + Text("[Terms](https://www.rareimagery.net/terms)")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(AppColor.textSecondary)
        + Text(" and ")
            .font(.system(size: 11))
            .foregroundStyle(AppColor.textSecondary)
        + Text("[Privacy Policy](https://www.rareimagery.net/privacy)")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(AppColor.textSecondary)
        + Text(".")
            .font(.system(size: 11))
            .foregroundStyle(AppColor.textSecondary)
    }

    // MARK: - Helpers

    /// Real subdomain from the signed-in session, NOT a placeholder.
    /// Falls back to `rare.rareimagery.net` if `displayHandle` somehow
    /// isn't surfaced (defensive — shouldn't happen post-provision).
    private var storefrontURL: URL {
        let slug = state.session.displayHandle ?? "rare"
        return URL(string: "https://\(slug).rareimagery.net") ?? URL(string: "https://www.rareimagery.net")!
    }

    /// Pre-populated share text. Uses the draft title when present so
    /// the tweet draft is product-aware: "Just dropped <Title> on my
    /// store — <URL>". Falls back to a generic open if the draft isn't
    /// set (defensive — Continue is only reachable after .ready).
    private var shareMessage: String {
        if let title = viewModel.createdDraft?.title, !title.isEmpty {
            return "Just dropped \(title) on my store — check it out:"
        }
        return "Just opened my store — come take a look:"
    }
}

#Preview {
    FirstProductCompleteView(
        viewModel: {
            let vm = FirstProductViewModel()
            vm.createdDraft = ProductDraft(
                title: "Vintage Denim Jacket",
                summary: "Classic washed denim with great texture.",
                suggestedPriceLow: 28,
                suggestedPriceHigh: 42,
                tags: ["denim", "vintage", "jacket"]
            )
            return vm
        }(),
        onFinish: {}
    )
    .environment(AppState())
    .preferredColorScheme(.dark)
}
