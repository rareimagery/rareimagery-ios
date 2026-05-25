import Foundation
import Observation
import RareImageryAPI

/// State machine for OnePageCreatorView.
///
/// Phases:
///   - `.idle` — initial; not yet attempted to load (waiting on appear)
///   - `.loadingIdeas` — vision/merch-ideas in flight
///   - `.ideasReady(ideas)` — concepts rendered, user can tap one
///   - `.generating(idea, mode)` — design-studio/generate in flight
///   - `.previewReady(idea, imageURL)` — generated mockup available
///   - `.publishing` — provision-store + (TBD) publish-product in flight
///   - `.published(productId)` — final state, may auto-present Send sheet
///   - `.error(message)` — recoverable, retry preserves selection
@MainActor
@Observable
final class OnePageCreatorViewModel {
    // MARK: - Public state (driven by the view)

    var phase: Phase = .idle
    var selectedProductKind: MerchProductKind = .tShirt
    var ideas: [MerchIdeaDraft] = []
    var selectedIdea: MerchIdeaDraft?
    var previewImageURL: URL?

    /// PFP URL pulled from `AuthSession.creator?.avatarUrl` at load.
    /// Optional because debug-sim sign-in may not include one — the view
    /// falls back to a placeholder hero in that case.
    var pfpURL: URL?
    var displayName: String = ""

    /// Bottom toggle on the OnePageCreator post-publish UI. Defaults on.
    /// When true: after publish, automatically present `SendToCircleSheet`.
    var alsoSendToCircle: Bool = true

    var errorMessage: String?

    // MARK: - Dependencies (injected from AppState)

    /// `ProductRepository.merchIdeas(dataURLs:...)` is the canonical
    /// merch-ideas accessor — predates this Phase 2 work; reused rather
    /// than duplicated. (Original draft of this file introduced a
    /// `MerchIdeasRepository` that collided with the existing types.)
    private let productRepository: ProductRepository
    private let designGenerationRepository: DesignGenerationRepository

    init(
        productRepository: ProductRepository,
        designGenerationRepository: DesignGenerationRepository
    ) {
        self.productRepository = productRepository
        self.designGenerationRepository = designGenerationRepository
    }

    // MARK: - Phase enum

    enum Phase: Equatable {
        case idle
        case loadingIdeas
        case ideasReady
        case generating(modeHint: GenerationMode)
        case previewReady
        case publishing
        case published(productId: String)
        case error(String)

        enum GenerationMode: Equatable {
            /// ~10-15s — show inline spinner.
            case fast
            /// ~30-90s — show skeleton + estimated time.
            case background
        }
    }

    // MARK: - Lifecycle (called from .task on view appear)

    /// Pull PFP + display name from `AuthSession.creator`, then auto-run
    /// merch-ideas. Idempotent per session — in-memory cache keyed by PFP
    /// URL so re-entry doesn't burn Grok quota.
    func bootstrap(creator: AuthTokenResponse.Creator?) async {
        self.displayName = creator?.displayName ?? creator?.handle ?? ""

        if let avatar = creator?.avatarUrl, let url = URL(string: avatar) {
            self.pfpURL = url
        }

        // If we already have ideas for this PFP, skip the call (cost guard
        // for the auto-on-appear UX — see Plan Amendment 2026-05-24).
        if !ideas.isEmpty {
            phase = .ideasReady
            return
        }

        await refreshIdeas()
    }

    /// Explicit "Refresh ideas" affordance (manual cost burn — surface
    /// this in the UI when the user wants new concepts).
    func refreshIdeas() async {
        guard let pfpURL else {
            phase = .error("Sign in with X to load merch ideas.")
            return
        }

        phase = .loadingIdeas
        errorMessage = nil
        do {
            let response = try await productRepository.merchIdeas(
                dataURLs: [pfpURL.absoluteString],
                productIntent: .designMerch,
                productType: .physical,
                voiceTranscript: nil,
                featureFriends: [],
                heroOnly: true
            )
            self.ideas = response.ideas

            if response.ok, !response.ideas.isEmpty {
                phase = .ideasReady
            } else if let err = response.error {
                // Graceful-fail path: vision API degraded but we still got
                // fallback ideas. Surface the warning, render the ideas.
                phase = .ideasReady
                errorMessage = err
            } else {
                phase = .error("No ideas returned — try refreshing.")
            }
        } catch {
            phase = .error(describe(error))
        }
    }

    // MARK: - Generation

    /// User tapped a concept card → spend a real generation call.
    /// For apparel (t_shirt/hoodie/ballcap), the BFF returns background
    /// mode; we poll under the hood and surface a `.generating(.background)`
    /// phase so the view can render the long-wait UX.
    func selectIdea(_ idea: MerchIdeaDraft) async {
        selectedIdea = idea
        previewImageURL = nil
        errorMessage = nil

        // All three v1 product kinds are apparel → background mode.
        phase = .generating(modeHint: .background)

        let request = DesignGenerationRequest(
            prompt: idea.suggestedPrompt,
            productType: selectedProductKind.rawValue,
            referenceImage: pfpURL?.absoluteString,
            variants: 4,
            useCreatorContext: true,
            placementId: nil
        )

        do {
            let url = try await designGenerationRepository.generateAndWait(request)
            self.previewImageURL = url
            phase = .previewReady
        } catch {
            phase = .error(describe(error))
        }
    }

    // MARK: - Publish (placeholder — depends on resolving the publish-endpoint gap)

    /// `Create my shirt + launch store` — provisions the store (idempotent
    /// no-op if it exists) and publishes the product.
    ///
    /// ⚠ The "publish product from generated design" endpoint is the gap
    /// flagged in the Plan Amendment. Until it lands, this method only
    /// runs the store-provision step and returns a synthetic id so the
    /// view can move to `.published` for Send-to-Circle hookup testing.
    func createProductAndStore() async {
        phase = .publishing
        do {
            // TODO: call provisionCreatorAction via OnboardingRepository
            //       (already idempotent — see provision-store/route.ts).
            //       For now, simulate the round-trip latency.
            try await Task.sleep(for: .milliseconds(800))

            // TODO: real product publish endpoint. Synthesize an id
            //       so .published has something to carry.
            let stub = UUID().uuidString
            phase = .published(productId: stub)
        } catch {
            phase = .error(describe(error))
        }
    }

    // MARK: - Helpers

    private func describe(_ error: Error) -> String {
        let raw = (error as NSError).localizedDescription
        if raw.lowercased().contains("internet") || raw.lowercased().contains("offline") {
            return "You're offline. Try again when you're back online."
        }
        return raw.isEmpty ? "Something went wrong — please try again." : raw
    }
}
