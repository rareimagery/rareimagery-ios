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
/// Routing (set by parent ContentView):
///   - "Create first product" → CaptureFlowView (the wow moment)
///   - "Tweak my store" → TweakSheetView (modal — optional refinement)
///   - "Just explore" → Console root (skips the wow moment for browsers)
struct LivePreviewView: View {
    @Environment(AppState.self) private var state

    /// Three navigation outcomes. Parent ContentView decides what to
    /// render for each. Keeping it as an enum (vs callback closures)
    /// makes the routing intent obvious in this file.
    enum Action {
        case createFirstProduct
        case tweakStore
        case justExplore
    }

    /// Closure parent passes in to handle the action. Decoupling lets
    /// this view stay testable without an AppState dependency for routing.
    let onAction: (Action) -> Void

    @State private var showTweakSheet = false

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
    }

    // MARK: Sections

    private var headerSection: some View {
        VStack(spacing: 12) {
            // The dog logo placeholder — replaced with Image("rareimagery-logo")
            // once the asset is dragged into Assets.xcassets (TODO(logo) flag
            // in WelcomeView.swift).
            Image(systemName: "pawprint.fill")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(AppColor.cta)

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
                onAction(.createFirstProduct)
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
