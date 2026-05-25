import SwiftUI
import RareImageryAPI

/// The "You're live" screen — first thing a new creator sees after the
/// X OAuth callback. Replaces the prior 4-step wizard with a
/// "Confirm don't ask" pattern.
///
/// Goals:
///   1. Show the user their store is REAL and LIVE in <2 seconds
///   2. Make "Create your first product" the primary path (the magic
///      moment that defines RareImagery)
///   3. Make refinement optional, not blocking
///
/// Voice: Rare the mascot does the welcoming. Warm, brief, direct.
///
/// Routing:
///   - "Create your first product" → presents `FirstProductFlowView` as
///     a `.fullScreenCover` INTERNAL to this view. On finish that flow
///     flips `hasSeenLivePreview = true` itself and dismisses; on
///     cancel it just dismisses (user returns here to pick another
///     action).
///   - "Tweak my store first" → `TweakSheetView` (sheet — optional
///     refinement; flipping `hasSeenLivePreview` is the user's call
///     via the explicit Save/Continue inside the sheet).
///   - "Just explore" → fires `onAction(.justExplore)`; parent
///     `ContentView` flips `hasSeenLivePreview` and routes to the
///     main app.
struct LivePreviewView: View {
    @Environment(AppState.self) private var state

    /// Navigation outcomes the parent needs to know about. The primary
    /// "Create your first product" CTA is now handled internally via
    /// `.fullScreenCover` — the parent doesn't need a case for it
    /// because `FirstProductFlowView` owns its own finish + dismiss
    /// behavior. Kept as an enum (vs. closures-per-action) so the
    /// remaining parent-driven actions stay self-documenting.
    enum Action {
        case tweakStore
        case justExplore
    }

    /// Closure parent passes in to handle the action. Decoupling lets
    /// this view stay testable without an AppState dependency for routing.
    let onAction: (Action) -> Void

    @State private var showTweakSheet = false

    /// Drives the primary CTA's `.fullScreenCover` presenting the new
    /// 3-screen first-product wizard. Internal to this view — the
    /// parent doesn't need to know.
    @State private var showFirstProductFlow = false

    var body: some View {
        ZStack {
            AppColor.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Header — Rare's voice
                    headerSection
                        .padding(.top, 16)

                    // The hero — their live store, rendered from X data
                    LiveStorePreview(
                        displayName: state.session.displayHandle ?? "your name",
                        handle: state.session.claims?.handle ?? "yourname",
                        bio: bioFromClaims,
                        avatarURL: avatarURLFromClaims,
                        bannerURL: nil,  // X banner URL isn't in MobileClaims; fetched via Drupal later
                        colorScheme: .default,
                        slug: state.session.claims?.slug ?? "yourname"
                    )
                    .padding(.horizontal, 20)

                    // CTAs — three tiers, primary leans into the wow moment
                    actionStack
                        .padding(.horizontal, 20)

                    Spacer().frame(height: 24)
                }
            }
        }
        .sheet(isPresented: $showTweakSheet) {
            TweakSheetView()
        }
        .fullScreenCover(isPresented: $showFirstProductFlow) {
            FirstProductFlowView()
        }
    }

    // MARK: Sections

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image("rareimagery-logo")
                .resizable()
                .scaledToFit()
                .frame(height: 56)

            Text("You're live")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(AppColor.textPrimary)

            Text("Rare set up your store. Tap below to add your first product, or tweak the look first.")
                .font(.system(size: 15))
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 32)
        }
    }

    private var actionStack: some View {
        VStack(spacing: 12) {
            Button {
                // Primary CTA opens the 3-screen FirstProduct wizard
                // INTERNALLY via fullScreenCover. The wizard owns its
                // own finish + dismiss (it flips hasSeenLivePreview
                // itself on Screen 3's "Continue to Rare"). On user
                // cancel, the cover dismisses and we stay on this
                // welcome screen so they can pick another path.
                showFirstProductFlow = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Create your first product")
                        .font(.system(size: 17, weight: .semibold))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(AppColor.cta)
                .clipShape(Capsule())
            }

            Button {
                showTweakSheet = true
            } label: {
                Text("Tweak my store first")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppColor.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppColor.surface)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(AppColor.border, lineWidth: 1))
            }

            Button {
                onAction(.justExplore)
            } label: {
                Text("Just explore")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColor.textSecondary)
                    .padding(.vertical, 8)
            }
        }
    }

    // MARK: Helpers

    /// Bio isn't in MobileClaims today — comes from the Drupal profile.
    /// Until we add a `/api/me` call to backfill, fall back to a friendly
    /// placeholder. The TweakSheetView lets the user enter / edit a bio
    /// directly, which is the real fix until iOS reads /api/me.
    private var bioFromClaims: String {
        // Placeholder. Replace with `state.creator?.bio ?? ""` when the
        // Auth response surfaces bio (currently AuthTokenResponse.Creator
        // has displayName + avatarUrl but not bio).
        ""
    }

    /// Avatar URL comes from AuthTokenResponse.creator.avatarUrl which
    /// IS surfaced today via signMobileTokens' return.
    private var avatarURLFromClaims: URL? {
        guard let url = state.session.creator?.avatarUrl, !url.isEmpty else {
            return nil
        }
        return URL(string: url)
    }
}

#Preview {
    LivePreviewView(onAction: { action in
        print("Action: \(action)")
    })
    .environment(AppState())
    .preferredColorScheme(.dark)
}
