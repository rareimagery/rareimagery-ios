import SwiftUI
import RareImageryAPI

/// Act 4 of the app flow ("Launch your store", mockup screens 4 + 4b):
/// banner/avatar imported from X, the in-session products with ▲▼
/// reorder, and the gold "Launch store" CTA. Launching flips to the
/// full-screen "You're live." celebration.
///
/// Products are the drafts created in this session (no product-list
/// endpoint exists on the BFF yet — see CLAUDE.md §3, GET is by-uuid
/// only). Reordering is local-only for the same reason.
struct StoreEditorView: View {
    @Environment(AppState.self) private var state

    /// Drafts created during the flow, editor-ordered.
    @State var products: [ProductDraft]

    /// Fires from the launched screen's final CTA — parent flips
    /// `hasSeenLivePreview` and dismisses the wizard cover.
    let onFinish: () -> Void

    private enum Phase { case editing, launching, launched }
    @State private var phase: Phase = .editing

    var body: some View {
        ZStack {
            AppColor.vaultGradient.ignoresSafeArea()
            switch phase {
            case .editing, .launching: editor
            case .launched: launchedView
            }
        }
        .animation(.easeInOut(duration: 0.3), value: phase == .launched)
    }

    // MARK: - Editor (mockup screen 4)

    private var editor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Your store")
                        .font(AppFont.display(28, .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("DRAFT")
                        .font(AppFont.mono(10, .semibold)).tracking(1.5)
                        .foregroundStyle(AppColor.gold)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .overlay(Capsule().stroke(AppColor.borderGold, lineWidth: 1))
                }

                // Banner + avatar — imported from X at provision time.
                LiveStorePreview(
                    displayName: state.session.displayHandle ?? "Your name",
                    handle: state.session.claims?.handle ?? "yourname",
                    bio: "",
                    avatarURL: nil,
                    bannerURL: nil,
                    colorScheme: .default,
                    slug: slug
                )

                Text("PRODUCTS · TAP ARROWS TO REORDER")
                    .font(AppFont.mono(10.5, .semibold)).tracking(2)
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.top, 6)

                VStack(spacing: 8) {
                    ForEach(products.indices, id: \.self) { i in
                        productRow(index: i)
                    }
                }

                Spacer(minLength: 20)

                FunnelGoldButton(
                    title: phase == .launching ? "Publishing to \(storeURLDisplay)…" : "Launch store"
                ) { launch() }
                .disabled(phase == .launching)
                .opacity(phase == .launching ? 0.7 : 1)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
    }

    private func productRow(index: Int) -> some View {
        let draft = products[index]
        return HStack(spacing: 12) {
            Text(String(format: "F%02d", index + 1))
                .font(AppFont.mono(11, .semibold))
                .foregroundStyle(AppColor.gold)
                .frame(width: 40, height: 40)
                .background(AppColor.goldSoft, in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(draft.title)
                    .font(AppFont.display(14.5, .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let price = draft.priceDisplay {
                    Text(price)
                        .font(AppFont.mono(12, .regular))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            Spacer(minLength: 0)

            reorderButton("chevron.up", enabled: index > 0) {
                products.swapAt(index, index - 1)
            }
            reorderButton("chevron.down", enabled: index < products.count - 1) {
                products.swapAt(index, index + 1)
            }
        }
        .padding(11)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }

    private func reorderButton(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(enabled ? .white : .white.opacity(0.25))
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        }
        .disabled(!enabled)
    }

    // MARK: - Launched (mockup screen 4b)

    private var launchedView: some View {
        VStack(spacing: 0) {
            Spacer()

            Text("STORE № 001 · LIVE")
                .font(AppFont.mono(10.5, .semibold)).tracking(2)
                .foregroundStyle(AppColor.gold)

            (Text("You're live") + Text(".").foregroundColor(AppColor.gold))
                .font(AppFont.display(36, .semibold))
                .foregroundStyle(.white)
                .padding(.top, 12)

            Text(storeURLDisplay)
                .font(AppFont.mono(14, .semibold))
                .foregroundStyle(AppColor.gold)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(AppColor.goldSoft, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColor.borderGold, lineWidth: 1))
                .padding(.top, 18)

            Spacer()

            VStack(spacing: 10) {
                Link(destination: storeURL) {
                    Text("Open store")
                        .font(AppFont.buttonLabel)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(AppColor.gold, in: RoundedRectangle(cornerRadius: 14))
                }
                Button(action: onFinish) {
                    Text("Continue to Rare")
                        .font(AppFont.bodyText(14))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
            }

            Text("Be Rare.")
                .font(AppFont.mono(12, .semibold)).tracking(3)
                .foregroundStyle(.white.opacity(0.4))
                .padding(.top, 14)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
    }

    // MARK: - Actions

    /// ponytail: no store-level launch endpoint exists (per-product
    /// /publish is a no-op today and in-session drafts carry no uuid) —
    /// the store is already live server-side at provision time. Swap the
    /// sleep for real per-product publish calls once drafts return uuids.
    private func launch() {
        phase = .launching
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            phase = .launched
        }
    }

    // MARK: - Helpers

    private var slug: String {
        state.session.claims?.slug ?? state.session.displayHandle ?? "yourname"
    }

    private var storeURLDisplay: String { "\(slug).rareimagery.net" }

    private var storeURL: URL {
        URL(string: "https://\(slug).rareimagery.net") ?? URL(string: "https://www.rareimagery.net")!
    }
}

#Preview {
    StoreEditorView(
        products: [
            ProductDraft(title: "Leica M3 Rangefinder", suggestedPriceLow: 1800, suggestedPriceHigh: 2400),
            ProductDraft(title: "Vintage Denim Jacket", suggestedPriceLow: 58, suggestedPriceHigh: 72),
        ],
        onFinish: {}
    )
    .environment(AppState())
    .preferredColorScheme(.dark)
}
