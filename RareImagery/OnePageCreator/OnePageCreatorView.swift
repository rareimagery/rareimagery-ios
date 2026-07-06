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
    /// Phase 3 — flipped true when an anonymous user taps an idea card.
    /// Drives the modal sign-up sheet (which currently posts a friendly
    /// hand-off — actual X sign-in flow wiring is a follow-up).
    @State private var showSignUpSheet = false

    /// Optional burst-capture inputs. When `vibePhotoURL` is set, the
    /// view skips the PFP path entirely and feeds the vibe photo to
    /// merch-ideas; `productPhotoURLs.first` becomes the `reference_image`
    /// for design-studio/generate. When nil, falls back to the PFP path
    /// for backwards compat (debug menus / pre-burst-capture entry points).
    let vibePhotoURL: URL?
    let productPhotoURLs: [URL]
    /// Invoked when the user taps "View my store" after a successful publish.
    /// Entry-point hosts use this to dismiss and flip onboarding flags.
    let onFinished: (() -> Void)?

    init(
        vibePhotoURL: URL? = nil,
        productPhotoURLs: [URL] = [],
        onFinished: (() -> Void)? = nil
    ) {
        self.vibePhotoURL = vibePhotoURL
        self.productPhotoURLs = productPhotoURLs
        self.onFinished = onFinished
    }

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
                let vm = OnePageCreatorViewModel(
                    productRepository: state.productRepository,
                    designGenerationRepository: state.designGenerationRepository,
                    publishProductRepository: state.publishProductRepository,
                    vibePhotoURL: vibePhotoURL,
                    productPhotoURLs: productPhotoURLs
                )
                // Phase 3 wiring: ViewModel stays ignorant of session state.
                // View provides callbacks that talk to AppState.
                vm.requiresAuthForGeneration = state.session.isAnonymous
                vm.onIdeasSpent = { [weak state] in
                    await state?.recordAnonymousFreeUseSpent()
                }
                vm.onGenerationGated = {
                    showSignUpSheet = true
                }
                viewModel = vm
            } else {
                // Keep the gating flag in sync if session state changes
                // mid-session (e.g. user signs in via the modal, returns
                // to OnePageCreator with a real token in `.accessToken`).
                viewModel?.requiresAuthForGeneration = state.session.isAnonymous
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

                // Phase 3.2 — trial counter chip. Visible only while the
                // user is anonymous AND has free uses left. SignUpReminderBanner
                // picks up at 0 (rendered near the CTA below), so this never
                // shows alongside the banner. Pulled to a tight negative
                // top-pad to feel like part of the hero composition rather
                // than a separate row.
                if state.session.isAnonymous && state.session.freeUsesRemaining > 0 {
                    FreeUsesChip(remaining: state.session.freeUsesRemaining)
                        .padding(.top, -16)
                }

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

                // Phase 3 — persistent soft reminder when the anonymous
                // trial user has spent their 3 free vibe-photo ideas.
                // The wall on actual generation lives in
                // OnePageCreatorViewModel.selectIdea (via
                // `requiresAuthForGeneration`); this banner is the
                // ambient nudge before they hit it.
                if state.session.shouldShowSignUpReminder {
                    SignUpReminderBanner(onConnectX: {
                        showSignUpSheet = true
                    })
                }

                CreateAndLaunchButton(
                    state: buttonState(for: viewModel),
                    action: {
                        if case .published = viewModel.phase {
                            onFinished?()
                            return
                        }
                        // Same gating for the bottom CTA — Create+Launch
                        // also requires X auth (provision-store + publish).
                        if state.session.isAnonymous {
                            showSignUpSheet = true
                        } else {
                            Task { await runPublish(viewModel: viewModel) }
                        }
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
        .sheet(isPresented: $showSignUpSheet) {
            // Phase 3.1 — present the existing SignInView in the sheet.
            // Zero new auth code: SignInView's AuthCoordinator handles
            // ASWebAuthenticationSession + token exchange + AuthSession
            // state transition. The observer below catches the
            // .anonymous → .signedIn flip and dismisses this sheet
            // automatically (the user doesn't have to tap Done).
            SignInView()
                .environment(state)
        }
        .onChange(of: state.session.isSignedIn) { _, isSignedIn in
            // The conversion moment. When AuthCoordinator completes the
            // X OAuth round-trip, AuthSession.apply(tokens:) flips status
            // to .signedIn → this fires. Two things happen:
            //   1. Dismiss the sign-up sheet (the auth flow already
            //      collapsed back from ASWebAuthenticationSession; the
            //      SignInView underneath has nothing more to do).
            //   2. Clear the ViewModel's generation gate so a subsequent
            //      idea tap proceeds straight into design-studio/generate
            //      instead of re-opening this same sheet.
            guard isSignedIn else { return }
            showSignUpSheet = false
            // Inside content(viewModel:), the parameter is non-optional.
            // Mutating .requiresAuthForGeneration here flows through to
            // the @State-backed @Observable instance held one level up.
            viewModel.requiresAuthForGeneration = false
        }
        // Phase 3.3 — funnel events from the View side. ViewModel emits
        // events it has direct context for; these two need View-level
        // state that doesn't belong in the VM.
        .onChange(of: state.session.shouldShowSignUpReminder) { wasShowing, isShowing in
            // `false → true` transition only — repeat re-renders don't
            // re-fire. Matches the spec: "first time the banner becomes
            // visible," not every layout pass.
            if !wasShowing && isShowing {
                Analytics.record(.signUpReminderShown)
            }
        }
        .onChange(of: showSignUpSheet) { wasShown, isShown in
            // Sheet present → user is now looking at SignInView. Counts
            // as auth-flow initiated regardless of which CTA triggered
            // it (banner button, gated idea tap, or Create+Launch).
            if !wasShown && isShown {
                Analytics.record(.xAuthInitiatedFromReminder)
            }
        }
        .onChange(of: state.session.freeUsesRemaining) { _, remaining in
            // Pair with the ViewModel's `recordIdeasSpentEvent`. The VM
            // can't reach `state.session.freeUsesRemaining` itself, so
            // the View observes the decrement and records the post-spend
            // count. Only fires while anonymous (the counter doesn't
            // decrement otherwise).
            guard state.session.isAnonymous else { return }
            Analytics.record(.freeMerchIdeasUsed(remaining: remaining))
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

/// Presents `OnePageCreatorView` inside a `NavigationStack` with a close
/// button — used by fullScreenCover entry points (Live Preview, Home tab).
struct OnePageCreatorHostView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    let vibePhotoURL: URL?
    let productPhotoURLs: [URL]
    /// When true, a successful publish + "View my store" also flips
    /// `hasSeenLivePreview` so `ContentView` routes to the main app.
    var markLivePreviewComplete: Bool = false

    init(
        vibePhotoURL: URL? = nil,
        productPhotoURLs: [URL] = [],
        markLivePreviewComplete: Bool = false
    ) {
        self.vibePhotoURL = vibePhotoURL
        self.productPhotoURLs = productPhotoURLs
        self.markLivePreviewComplete = markLivePreviewComplete
    }

    var body: some View {
        NavigationStack {
            OnePageCreatorView(
                vibePhotoURL: vibePhotoURL,
                productPhotoURLs: productPhotoURLs,
                onFinished: finishAfterPublish
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .environment(state)
        .tint(AppColor.accent)
        .preferredColorScheme(.dark)
    }

    private func finishAfterPublish() {
        if markLivePreviewComplete {
            state.session.hasSeenLivePreview = true
        }
        dismiss()
    }
}
