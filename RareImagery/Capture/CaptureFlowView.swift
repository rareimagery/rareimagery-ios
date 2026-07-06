import SwiftUI
import RareImageryAPI

struct CaptureFlowView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ZStack {
            CaptureView()

            switch state.capture.phase {
            case .working:
                overlay(title: "Analyzing", subtitle: "Reading your hero shot")
            case .ready(let draft):
                DraftPreview(draft: draft)
            case .error(let message):
                errorBanner(message: message)
            case .idle, .picking:
                EmptyView()
            }
        }
    }

    private func overlay(title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(AppColor.accent)
                .controlSize(.large)
            Text(title).font(AppFont.title).foregroundStyle(AppColor.textPrimary)
            Text(subtitle).font(AppFont.callout).foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.background.opacity(0.92))
    }

    private func errorBanner(message: String) -> some View {
        VStack {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.orange)
                Text(message)
                    .font(AppFont.callout)
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.center)
                Button("Dismiss") {
                    state.capture.phase = .idle
                }
                .padding(.top, 4)
                .tint(AppColor.accent)
            }
            .padding(20)
            .background(AppColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }
}

private struct DraftPreview: View {
    let draft: ProductDraft
    @Environment(AppState.self) private var state
    @State private var coordinator = AuthCoordinator()
    @State private var showSell = false
    @State private var isAuthenticating = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(draft.title)
                    .font(AppFont.title)
                    .foregroundStyle(AppColor.textPrimary)

                if let summary = draft.summary {
                    Text(summary)
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary.opacity(0.9))
                }

                if let description = draft.description {
                    Text(description)
                        .font(AppFont.body)
                        .foregroundStyle(AppColor.textSecondary)
                }

                HStack(spacing: 8) {
                    if let cat = draft.category { labelChip(cat.displayName) }
                    if let cond = draft.condition { labelChip(cond.displayName) }
                    if let brand = draft.brand { labelChip(brand) }
                    if let price = draft.priceDisplay { labelChip(price) }
                    if draft.handmade == true { labelChip("Handmade") }
                }

                if let tags = draft.tags, !tags.isEmpty {
                    Text(tags.map { "#\($0)" }.joined(separator: " "))
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }

                if let flags = draft.flags, !flags.isEmpty {
                    Text("Flags: \(flags.joined(separator: ", "))")
                        .font(AppFont.caption)
                        .foregroundStyle(.orange)
                }

                if let conf = draft.confidence {
                    Text("Confidence: \(Int((conf * 100).rounded()))%")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }

                Spacer(minLength: 24)

                sellCTA

                Button("New capture") {
                    state.capture.reset()
                }
                .buttonStyle(.bordered)
                .tint(AppColor.textSecondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppColor.background)
        .sheet(isPresented: $showSell) {
            QuickProductView(draft: draft, heroImageData: state.capture.hero?.jpegData)
        }
    }

    /// Value-first hook: capture + valuation are free and pre-login; the account
    /// wall sits here at the sell step. Anonymous → X sign-in (the draft persists
    /// in the capture session through auth); signed-in → the sell sheet.
    /// (Real storeless-draft adoption at signup is a backend open-loop.)
    @ViewBuilder private var sellCTA: some View {
        Button {
            if state.session.isSignedIn {
                showSell = true
            } else {
                Task {
                    isAuthenticating = true
                    let draftToken = state.session.isAnonymous ? (try? await state.keychain.get(.pendingDraftToken)) : nil
                    await coordinator.signInWithX(state: state, draftToken: draftToken)
                    isAuthenticating = false
                }
            }
        } label: {
            HStack(spacing: 8) {
                if isAuthenticating { ProgressView().tint(.black) }
                Text(isAuthenticating ? "Connecting to X…" : (state.session.isAnonymous ? "Claim this draft" : "Create your store to sell"))
                    .font(AppFont.buttonLabel)
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(AppColor.cta)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(isAuthenticating)
    }

    private func labelChip(_ text: String) -> some View {
        Text(text)
            .font(AppFont.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AppColor.surface)
            .clipShape(Capsule())
            .foregroundStyle(AppColor.textPrimary)
    }
}

/// Drives the `/api/vision/analyze` call. JSON + base64 data URLs.
/// Each shot is pre-compressed to ≤1280px JPEG 0.85 before encoding.
/// For multi-photo: only the user-selected 1-2 favorites are sent
/// (for Grok Vision analysis + as official product hero pictures).
/// Matches web PhotoCurationGrid + spec "select 1-2, trash the rest".
@MainActor
enum CaptureCoordinator {
    static func run(state: AppState) async {
        let capture = state.capture
        let products = state.productRepository

        guard capture.canAnalyze else { return }
        capture.phase = .working

        // ponytail: stub path — return a mock valuation without the network so
        // the value-first funnel is testable before the backend is connected.
        // Flip `AppState.useMocks` to false to use the real productRepository.
        if state.useMocks {
            try? await Task.sleep(for: .seconds(1))
            capture.phase = .ready(Self.mockDraft())
            return
        }

        // Only send the selected favorites (1-2) for analysis.
        // Order: put the current hero first if it's selected, else first selected.
        let selectedShots = capture.shots.filter { capture.selectedFavoriteIds.contains($0.id) }
        guard !selectedShots.isEmpty else {
            capture.phase = .error("No favorites selected for analysis")
            return
        }

        let orderedShots: [CaptureSession.Shot] = {
            if let hero = capture.hero, capture.selectedFavoriteIds.contains(hero.id) {
                var rest = selectedShots.filter { $0.id != hero.id }
                return [hero] + rest
            } else {
                return selectedShots
            }
        }()

        let dataURLs = orderedShots.map { ImageCompression.toBase64DataURL($0.jpegData) }

        do {
            // heroOnly: false since we may send 1-2; the backend will use all provided
            // for analysis (and they become the product pictures).
            let result = try await products.analyze(
                dataURLs: dataURLs,
                intent: capture.intent,
                voiceTranscript: capture.voiceTranscript.isEmpty ? nil : capture.voiceTranscript,
                heroOnly: false,
                mode: .product
            )
            if let token = result.draftToken {
                try? await state.keychain.set(token, for: .pendingDraftToken)
            }
            capture.phase = .ready(result.draft)
        } catch {
            capture.phase = .error(message(error))
        }
    }

    private static func message(_ error: Error) -> String {
        if let api = error as? APIError { return api.userFacingMessage }
        return error.localizedDescription
    }

    /// ponytail: hardcoded valuation for the stubbed (useMocks) path. Mirrors a
    /// realistic `/api/vision/analyze` resale draft so the result/hook screen has
    /// a value to show without a backend.
    private static func mockDraft() -> ProductDraft {
        ProductDraft(
            title: "Vintage Levi's Denim Jacket",
            summary: "Washed indigo trucker jacket — looks early-'90s, great fade.",
            description: "Heavyweight denim, classic red tab, light wear at the cuffs. A solid resale staple.",
            category: nil,
            condition: nil,
            brand: "Levi's",
            suggestedPriceLow: 45,
            suggestedPriceHigh: 80,
            tags: ["denim", "vintage", "levis", "jacket"],
            handmade: false,
            confidence: 0.86,
            flags: nil
        )
    }
}
