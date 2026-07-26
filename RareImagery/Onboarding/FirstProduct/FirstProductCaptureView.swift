import SwiftUI
import RareImageryAPI

/// Screen 2 of the first-product wizard. Single camera path:
///
///   1. User taps "Take a photo of your product" → CaptureFlowView
///      sheet presents (the existing capture + analyze pipeline)
///   2. On `state.capture.phase == .ready(draft)`, auto-dismiss the
///      sheet and surface a result card here (title / summary /
///      price range / tags)
///   3. "Create & Add to Store" advances to Screen 3
///   4. "Take another photo" lets the user retry without losing their
///      Screen 1 chip selections
///
/// The "Use a Printful template" card from the user's original sketch
/// is **deferred** — only the camera path ships in v1. A muted "Coming
/// soon: Printful templates" hint sits below the camera card so users
/// know it's planned but unimplemented.
struct FirstProductCaptureView: View {
    @Environment(AppState.self) private var state
    @Bindable var viewModel: FirstProductViewModel

    @State private var showCaptureSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                hero
                    .padding(.top, 12)

                if let draft = viewModel.createdDraft {
                    resultCard(for: draft)
                    primaryCTA
                } else {
                    captureCard
                    printfulHint
                }

                if let errorMessage = viewModel.errorMessage {
                    errorBanner(message: errorMessage)
                }

                Spacer().frame(height: 32)
            }
            .padding(.horizontal, 20)
        }
        .background(AppColor.background)
        .sheet(isPresented: $showCaptureSheet) {
            // Present CaptureFlowView WITHOUT a NavigationStack wrapper —
            // its own .toolbar (with "Sign out") silently no-ops without
            // a parent nav bar, which is the right behavior mid-wizard.
            CaptureFlowView()
        }
        .onChange(of: state.capture.phase) { _, newPhase in
            // Only react when the sheet is open — otherwise the parent
            // app's CaptureFlowView (post-onboarding) drives this state
            // and we don't want unsolicited accepts.
            guard showCaptureSheet else { return }
            switch newPhase {
            case .ready(_, let draft):
                viewModel.acceptDraft(draft)
                showCaptureSheet = false
            case .error(let message):
                // Don't auto-dismiss — CaptureFlowView's own error banner
                // gives the user a Dismiss button to retry in-sheet. We
                // also record the message so a user-side swipe-down still
                // surfaces context on the result card.
                viewModel.recordCaptureError(message)
            default:
                break
            }
        }
        .onChange(of: showCaptureSheet) { _, isOpen in
            // Sheet just closed — reset capture state so the next "Take
            // another photo" tap starts from .idle regardless of how the
            // previous session ended. Our draft is already safely on the
            // view-model so this doesn't lose data.
            if !isOpen {
                state.capture.reset()
            }
        }
    }

    // MARK: - Sections

    private var hero: some View {
        VStack(spacing: 8) {
            Text("Create your first product")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)

            Text("Snap a photo — Rare will draft a title, summary, and a price range for you to refine.")
                .font(.system(size: 14))
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 16)
        }
    }

    private var captureCard: some View {
        Button {
            viewModel.resetCapture()
            showCaptureSheet = true
        } label: {
            VStack(spacing: 12) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(AppColor.cta)

                Text("Take a photo of your product")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)

                Text("Up to 5 shots — pick the best as your hero.")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColor.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(AppColor.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var printfulHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "shippingbox")
                .font(.system(size: 12))
            Text("Coming soon: Printful templates")
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(AppColor.textSecondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(AppColor.surface, in: Capsule())
        .overlay(Capsule().stroke(AppColor.border, lineWidth: 1))
    }

    private func resultCard(for draft: ProductDraft) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppColor.cta)
                    .font(.system(size: 18))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rare's draft")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColor.textSecondary)
                        .textCase(.uppercase)
                        .tracking(0.6)
                    Text(draft.title)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(AppColor.textPrimary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }

            if let summary = draft.summary, !summary.isEmpty {
                Text(summary)
                    .font(.system(size: 14))
                    .foregroundStyle(AppColor.textPrimary.opacity(0.85))
                    .lineSpacing(2)
            } else if let description = draft.description, !description.isEmpty {
                Text(description)
                    .font(.system(size: 14))
                    .foregroundStyle(AppColor.textPrimary.opacity(0.85))
                    .lineSpacing(2)
            }

            if let priceDisplay = draft.priceDisplay {
                HStack(spacing: 6) {
                    Text("Suggested price")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColor.textSecondary)
                        .textCase(.uppercase)
                        .tracking(0.6)
                    Text(priceDisplay)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColor.textPrimary)
                }
            }

            if let tags = draft.tags, !tags.isEmpty {
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(tags.prefix(8), id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppColor.background, in: Capsule())
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
            }

            Button {
                viewModel.resetCapture()
                showCaptureSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Take another photo")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(AppColor.textSecondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(AppColor.border, lineWidth: 1)
        )
    }

    private var primaryCTA: some View {
        Button {
            viewModel.advanceToComplete()
        } label: {
            HStack(spacing: 8) {
                Text("Create & Add to Store")
                    .font(.system(size: 16, weight: .semibold))
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(AppColor.cta)
            .clipShape(Capsule())
        }
    }

    private func errorBanner(message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.orange.opacity(0.5), lineWidth: 1)
        )
    }
}

#Preview {
    FirstProductCaptureView(viewModel: FirstProductViewModel())
        .environment(AppState())
        .preferredColorScheme(.dark)
}
