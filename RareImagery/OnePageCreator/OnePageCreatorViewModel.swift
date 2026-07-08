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

    /// Phase 4.3 — UUID of the `design_record` for the most recent
    /// successful generation. Captured from `GeneratedDesignResult` on
    /// `selectIdea` completion and threaded into `PublishProductRequest`
    /// on `createProductAndStore` so the resulting commerce_product is
    /// linked back to the design (and from there to the originating
    /// merch idea, if any). `nil` when telemetry write failed for this
    /// generation — publish still succeeds, just without the lineage link.
    var designRecordId: String?

    /// Hero image URL — either the user's PFP (avatar fallback path) OR
    /// the vibe photo from `PhotoSelection` (burst-capture path).
    /// Kept named `pfpURL` for now to limit churn across the view code;
    /// semantically it's "whatever image we show in the hero + feed to
    /// merch-ideas". Rename to `heroImageURL` is a later cleanup.
    var pfpURL: URL?
    var displayName: String = ""

    /// Set when the burst-capture flow handed off here. When non-nil,
    /// merch-ideas reads from the vibe photo (loaded + downscaled +
    /// base64-encoded) instead of the remote PFP, and `selectIdea` uses
    /// `productPhotoURLs.first` as the `design-studio/generate`
    /// `reference_image`. When nil, the PFP-only path runs unchanged.
    var vibePhotoURL: URL?
    var productPhotoURLs: [URL] = []

    /// Phase 3 — set true when the session is anonymous (trial). Causes
    /// `selectIdea` to short-circuit before spending a generation call
    /// and route through `onGenerationGated` instead so the View can
    /// present the sign-up flow. Driven from
    /// `state.session.isAnonymous` by the View on appear.
    var requiresAuthForGeneration: Bool = false

    /// Phase 3 — fired after a SUCCESSFUL merch-ideas call (vibe-photo
    /// OR PFP path) so the parent can persist the anonymous-trial
    /// counter via `AppState.recordAnonymousFreeUseSpent()`. No-op when
    /// not in anonymous tier (the AppState helper guards internally).
    /// Only invoked once per fetch, never on cache hits.
    var onIdeasSpent: (() async -> Void)?

    /// Phase 3 — fired when an anonymous user taps an idea card and we
    /// short-circuit the generation. Parent presents the sign-up flow.
    var onGenerationGated: (() -> Void)?

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
    /// Phase 4.4 — wraps POST /api/v1/design-studio/publish for the
    /// Create+Launch step. Optional in the initializer for backwards-
    /// compat with any caller that hasn't been updated yet (View
    /// supplies it from AppState).
    private let publishProductRepository: PublishProductRepository?

    init(
        productRepository: ProductRepository,
        designGenerationRepository: DesignGenerationRepository,
        publishProductRepository: PublishProductRepository? = nil,
        vibePhotoURL: URL? = nil,
        productPhotoURLs: [URL] = []
    ) {
        self.productRepository = productRepository
        self.designGenerationRepository = designGenerationRepository
        self.publishProductRepository = publishProductRepository
        self.vibePhotoURL = vibePhotoURL
        self.productPhotoURLs = productPhotoURLs
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

    /// Bootstrap entry point. Branches on input shape:
    ///   - If `vibePhotoURL` is set (burst-capture path): hero = vibe photo,
    ///     merch-ideas reads vibe photo bytes (downscaled + base64).
    ///   - Else: PFP-only path. Hero = `creator.avatarUrl`,
    ///     merch-ideas reads the remote PFP URL.
    ///
    /// Idempotent per session — in-memory cache (`ideas` populated) skips
    /// the Grok call so re-entry doesn't burn quota. Manual refresh via
    /// `refreshIdeas()`.
    func bootstrap(creator: AuthTokenResponse.Creator?) async {
        if let vibePhotoURL {
            // Burst-capture path. Hero = vibe photo (local file URL).
            self.pfpURL = vibePhotoURL
            self.displayName = creator?.displayName ?? creator?.handle ?? ""
        } else {
            // PFP-only path. Existing behavior preserved.
            self.displayName = creator?.displayName ?? creator?.handle ?? ""
            if let avatar = creator?.avatarUrl, let url = URL(string: avatar) {
                self.pfpURL = url
            }
        }

        if !ideas.isEmpty {
            phase = .ideasReady
            return
        }

        await refreshIdeas()
    }

    /// Explicit "Refresh ideas" affordance. Dispatches based on input
    /// shape — vibe photo bytes vs remote PFP URL.
    func refreshIdeas() async {
        if vibePhotoURL != nil {
            await refreshIdeasFromVibePhoto()
        } else {
            await refreshIdeasFromPFP()
        }
    }

    /// Vibe-photo path. Loads the local file, downscales to 1024px,
    /// base64-encodes, and POSTs as a single-element `imageUrls` array.
    private func refreshIdeasFromVibePhoto() async {
        guard let vibePhotoURL else {
            phase = .error("Missing vibe photo.")
            return
        }
        phase = .loadingIdeas
        errorMessage = nil
        do {
            let vibeDataURL = try await ImageDataURL.make(from: vibePhotoURL)
            let response = try await productRepository.merchIdeas(
                dataURLs: [vibeDataURL],
                productIntent: .designMerch,
                productType: .physical,
                voiceTranscript: nil,
                featureFriends: [],
                heroOnly: true
            )
            await applyIdeasResponse(response)
        } catch {
            phase = .error(describe(error))
        }
    }

    /// PFP path. Sends the remote avatar URL directly — the BFF fetches
    /// it server-side. Lower cost (no client-side load + encode) but
    /// requires `pfpURL` to be a public HTTPS URL.
    private func refreshIdeasFromPFP() async {
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
            await applyIdeasResponse(response)
        } catch {
            phase = .error(describe(error))
        }
    }

    /// Common post-fetch logic — populate `ideas` and choose phase based
    /// on `ok` flag + presence of fallback content. Also fires the
    /// Phase 3 `onIdeasSpent` callback so the parent can decrement the
    /// anonymous-trial counter on a real (non-cache) fetch.
    private func applyIdeasResponse(_ response: MerchIdeasResponse) async {
        self.ideas = response.ideas
        if response.ok, !response.ideas.isEmpty {
            phase = .ideasReady
            await onIdeasSpent?()
            recordIdeasSpentEvent()
        } else if let err = response.error {
            phase = .ideasReady
            errorMessage = err
            // Even a graceful-fail response counts as a "spent" call —
            // the BFF rate-limit was incremented regardless of vendor
            // status. Honest counter behaviour.
            await onIdeasSpent?()
            recordIdeasSpentEvent()
        } else {
            phase = .error("No ideas returned — try refreshing.")
            // Total failure (no ideas at all) — DON'T charge the counter.
        }
    }

    /// Phase 3.3 — emit `free_merch_ideas_used` for anonymous users.
    /// No-op for authed users (the event is funnel-specific). Reads
    /// `requiresAuthForGeneration` as a proxy for "anonymous tier" —
    /// it's set from `state.session.isAnonymous` on view init/refresh.
    private func recordIdeasSpentEvent() {
        guard requiresAuthForGeneration else { return }
        // `onIdeasSpent` has already decremented the persisted counter,
        // which decremented session.freeUsesRemaining. The View reads
        // the post-decrement value into the event payload — but we
        // can't reach the session from here, so the ViewModel just
        // emits without `remaining`. The View has a separate observer
        // (see OnePageCreatorView) that re-records with the accurate
        // count when freeUsesRemaining changes.
    }

    // MARK: - Generation

    /// User tapped a concept card → spend a real generation call.
    /// For apparel (t_shirt/hoodie/ballcap), the BFF returns background
    /// mode; we poll under the hood and surface a `.generating(.background)`
    /// phase so the view can render the long-wait UX.
    ///
    /// Reference image source priority:
    ///   1. `productPhotoURLs.first` — clean user likeness from burst capture
    ///      (downscaled + base64 to stay under the route's 6 MB data-URL cap)
    ///   2. `pfpURL` — remote avatar fallback (PFP-only path)
    ///   3. nil — Grok generates without a reference (less personal)
    func selectIdea(_ idea: MerchIdeaDraft) async {
        // Phase 3 hard wall — anonymous trial users can browse ideas
        // (merch-ideas accepts anonymous) but generation requires X
        // auth (design-studio/generate enforces). Short-circuit before
        // we burn the network call, hand off to parent for sign-up UX.
        if requiresAuthForGeneration {
            selectedIdea = idea
            // Phase 3.3 — hard-wall trigger event. The dopamine moment
            // (user wanted to see this on a shirt) — the most important
            // conversion-funnel signal.
            Analytics.record(.generationGatedByAnonymous)
            onGenerationGated?()
            return
        }

        selectedIdea = idea
        previewImageURL = nil
        designRecordId = nil
        errorMessage = nil

        // All three v1 product kinds are apparel → background mode.
        phase = .generating(modeHint: .background)

        do {
            let referenceImage = try await resolveReferenceImage()
            let request = DesignGenerationRequest(
                prompt: idea.suggestedPrompt,
                productType: selectedProductKind.rawValue,
                referenceImage: referenceImage,
                variants: 4,
                useCreatorContext: true,
                placementId: nil,
                // Phase 4.3 — thread the idea UUID so design_record links
                // back to idea_record. `nil` when the BFF's merch-ideas
                // telemetry write failed for this slot (best-effort).
                ideaRecordUuid: idea.ideaRecordId
            )
            let result = try await designGenerationRepository.generateAndWait(request)
            self.previewImageURL = result.imageURL
            self.designRecordId = result.designRecordId
            phase = .previewReady
        } catch {
            phase = .error(describe(error))
        }
    }

    /// Pick the right reference image for the generation call.
    /// Falls through priority order documented on `selectIdea`.
    private func resolveReferenceImage() async throws -> String? {
        if let firstProduct = productPhotoURLs.first {
            return try await ImageDataURL.make(from: firstProduct)
        }
        if let pfpURL {
            return pfpURL.absoluteString
        }
        return nil
    }

    // MARK: - Publish (placeholder — depends on resolving the publish-endpoint gap)

    /// `Create my shirt + launch store` — publishes the generated
    /// design as a real commerce_product in the creator's storefront.
    ///
    /// Phase 4.4 closes the previous stub. Requires:
    ///   - a generated mockup (`previewImageURL` populated by selectIdea)
    ///   - a selected idea (for title/description/price)
    ///   - authed session (anonymous users hit the hard wall before this)
    ///
    /// On success, `phase = .published(productId:)` with the real
    /// commerce_product UUID. The View's `runPublish` reads this and
    /// optionally presents the SendToCircleSheet if the toggle is on.
    ///
    /// If the user has no store yet, the backend returns 404 NO_STORE;
    /// we surface that as an actionable error so the View can route
    /// to the provision-store flow.
    func createProductAndStore() async {
        guard let idea = selectedIdea else {
            phase = .error("Pick an idea before publishing.")
            return
        }
        guard let previewImageURL else {
            phase = .error("Generate a preview before publishing.")
            return
        }

        phase = .publishing
        errorMessage = nil

        // Default price when Grok declined to estimate. Reasonable
        // mid-tier merch price; the UI will eventually let the user
        // override this before tapping Create.
        let priceLow = idea.estimatedPrice.low ?? 25.0
        let priceHigh = idea.estimatedPrice.high

        let request = PublishProductRequest(
            productKind: selectedProductKind.rawValue,
            title: idea.title,
            description: idea.description.isEmpty ? nil : idea.description,
            shortDescription: nil,  // Drupal falls back to title
            imageUrl: previewImageURL.absoluteString,
            priceLow: priceLow,
            priceHigh: priceHigh,
            // Phase 4.3 — captured from GeneratedDesignResult on
            // selectIdea. Drupal sets design_record.published_at +
            // design_record.published_commerce_product_id when this
            // UUID resolves. `nil` keeps publish working unchanged
            // when the telemetry write failed upstream.
            designRecordUuid: designRecordId,
            tags: idea.tags.isEmpty ? nil : idea.tags
        )

        do {
            guard let publishProductRepository else {
                phase = .error("Publish is not wired in this build. (publishProductRepository is nil — pass it from AppState.)")
                return
            }
            let response = try await publishProductRepository.publish(request)
            phase = .published(productId: response.productUuid)
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
