import SwiftUI
import RareImageryAPI

/// "One Page Creator" — replaces `FirstProductFlowView` per the
/// 2026-05-24 plan amendment (OnePageCreator supersedes the 3-screen wizard).
///
/// Core principle: **make the user the product first**. PFP →
/// Grok-generated merch concepts → tap one to spend a real image-gen call
/// → preview → "Create my shirt + launch store" (provisions store +
/// publishes product + optional Send-to-Circle).
///
/// Auto-runs `vision/merch-ideas` on appear (cached per session by PFP
/// URL to limit Grok cost — see ViewModel.bootstrap).
struct OnePageCreatorView: View {
    @Environment(AppState.self) private var state
    @State private var viewModel: OnePageCreatorViewModel?
    @State private var showSendToCircle = false

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel: viewModel)
            } else {
                ProgressView()
                    .tint(AppColor.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppColor.background)
            }
        }
        .task {
            // Lazily instantiate so the view doesn't construct a VM until
            // it has the AppState environment in scope.
            if viewModel == nil {
                viewModel = OnePageCreatorViewModel(
                    productRepository: state.productRepository,
                    designGenerationRepository: state.designGenerationRepository
                )
            }
            await viewModel?.bootstrap(creator: state.session.creator)
        }
    }

    @ViewBuilder
    private func content(viewModel: OnePageCreatorViewModel) -> some View {
        ScrollView {
            VStack(spacing: 28) {
                UserAsProductHero(
                    pfpURL: viewModel.pfpURL,
                    displayName: viewModel.displayName
                )

                VStack(alignment: .leading, spacing: 12) {
                    Text("What do you want to create?")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppColor.textPrimary)
                        .padding(.horizontal, 16)

                    ProductTypeChips(selected: Binding(
                        get: { viewModel.selectedProductKind },
                        set: { viewModel.selectedProductKind = $0 }
                    ))
                }

                previewSection(viewModel: viewModel)

                GrokSuggestionsSection(
                    ideas: viewModel.ideas,
                    isLoading: viewModel.phase == .loadingIdeas,
                    selectedIdea: viewModel.selectedIdea,
                    onSelect: { idea in
                        Task { await viewModel.selectIdea(idea) }
                    },
                    onRefresh: {
                        Task { await viewModel.refreshIdeas() }
                    }
                )

                alsoSendToCircleToggle(viewModel: viewModel)

                CreateAndLaunchButton(
                    state: buttonState(for: viewModel),
                    action: {
                        Task { await runPublish(viewModel: viewModel) }
                    }
                )
                .padding(.horizontal, 16)

                if let message = viewModel.errorMessage {
                    Text(message)
                        .font(AppFont.caption)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }
            .padding(.vertical, 20)
            .padding(.bottom, 40)
        }
        .background(AppColor.background.ignoresSafeArea())
        .navigationTitle("Create")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSendToCircle) {
            // SendToCircleSheet from Phase 1. It takes a ProductDraft —
            // synthesize a lightweight draft from the selected idea since
            // ProductDraft isn't tied to the visual generation flow yet.
            if let idea = viewModel.selectedIdea {
                SendToCircleSheet(draft: synthesizeDraft(from: idea, kind: viewModel.selectedProductKind))
                    .environment(state)
            }
        }
    }

    // MARK: - Preview slot

    @ViewBuilder
    private func previewSection(viewModel: OnePageCreatorViewModel) -> some View {
        switch viewModel.phase {
        case .generating(let mode):
            generatingPreview(mode: mode)
        case .previewReady:
            if let url = viewModel.previewImageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    default:
                        ProgressView().tint(AppColor.accent)
                    }
                }
                .frame(height: 280)
                .frame(maxWidth: .infinity)
                .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 16)
            }
        default:
            EmptyView()
        }
    }

    private func generatingPreview(mode: OnePageCreatorViewModel.Phase.GenerationMode) -> some View {
        VStack(spacing: 14) {
            ProgressView().tint(AppColor.accent)
            Text(mode == .background
                 ? "Painting your design… up to 90s"
                 : "Generating…")
                .font(AppFont.callout)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(height: 280)
        .frame(maxWidth: .infinity)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    // MARK: - Send-to-Circle toggle (only meaningful after preview)

    @ViewBuilder
    private func alsoSendToCircleToggle(viewModel: OnePageCreatorViewModel) -> some View {
        if case .previewReady = viewModel.phase {
            Toggle(isOn: Binding(
                get: { viewModel.alsoSendToCircle },
                set: { viewModel.alsoSendToCircle = $0 }
            )) {
                Label("Also send to Circle for feedback", systemImage: "person.3.fill")
                    .font(AppFont.callout)
                    .foregroundStyle(AppColor.textPrimary)
            }
            .tint(AppColor.accent)
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Helpers

    private func buttonState(for viewModel: OnePageCreatorViewModel) -> CreateAndLaunchButton.State {
        switch viewModel.phase {
        case .idle, .loadingIdeas, .ideasReady:
            return viewModel.selectedIdea == nil ? .waitingForIdea : .waitingForPreview
        case .generating:
            return .waitingForPreview
        case .previewReady:
            return .readyToCreate(productLabel: viewModel.selectedProductKind.label)
        case .publishing:
            return .publishing
        case .published:
            return .published
        case .error:
            return .readyToCreate(productLabel: viewModel.selectedProductKind.label)
        }
    }

    private func runPublish(viewModel: OnePageCreatorViewModel) async {
        await viewModel.createProductAndStore()
        if case .published = viewModel.phase, viewModel.alsoSendToCircle {
            showSendToCircle = true
        }
    }

    private func synthesizeDraft(from idea: MerchIdeaDraft, kind: MerchProductKind) -> ProductDraft {
        ProductDraft(
            title: idea.title,
            summary: idea.description.isEmpty ? nil : idea.description,
            description: idea.suggestedPrompt,
            category: nil,
            condition: nil,
            brand: nil,
            suggestedPriceLow: idea.estimatedPrice.low.map { Decimal($0) },
            suggestedPriceHigh: idea.estimatedPrice.high.map { Decimal($0) },
            tags: idea.tags,
            handmade: nil,
            confidence: nil,
            flags: (idea.flags ?? []).isEmpty ? nil : idea.flags
        )
    }
}
