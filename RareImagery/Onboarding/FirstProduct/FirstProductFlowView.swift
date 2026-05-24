import SwiftUI
import RareImageryAPI

/// Top-level coordinator for the 3-screen first-product wizard.
/// Presented as a `.fullScreenCover` from `LivePreviewView`'s primary
/// CTA. Owns the `FirstProductViewModel` and switches on its `phase`
/// to render the right screen.
///
/// Two exit paths:
///
///   1. **Cancel** (toolbar X) — dismisses the fullScreenCover without
///      flipping `hasSeenLivePreview`. User goes back to LivePreviewView
///      and can re-tap the primary CTA or pick another action.
///
///   2. **Continue to Rare** (Screen 3 CTA) — dismisses the cover AND
///      flips `state.session.hasSeenLivePreview = true`. ContentView's
///      next render routes to the main app (`CaptureFlowView`).
///
/// Each screen is a simple SwiftUI view that takes the shared
/// `@Bindable var viewModel: FirstProductViewModel` — keeps navigation
/// state in one place and lets the screens stay declarative.
@MainActor
struct FirstProductFlowView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel = FirstProductViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.background.ignoresSafeArea()

                Group {
                    switch viewModel.phase {
                    case .setup:
                        FirstProductSetupView(viewModel: viewModel)
                    case .capturing:
                        FirstProductCaptureView(viewModel: viewModel)
                    case .complete:
                        FirstProductCompleteView(
                            viewModel: viewModel,
                            onFinish: finishWizard
                        )
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppColor.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        // Cancel — back to LivePreviewView. Don't flip
                        // hasSeenLivePreview; the welcome screen is the
                        // natural fallback for "changed my mind."
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    .accessibilityLabel("Close")
                }

                ToolbarItem(placement: .principal) {
                    progressDots
                }
            }
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.25), value: viewModel.phase)
    }

    // MARK: - Helpers

    /// Inline navigation title. Per-screen so the bar tells the user
    /// where they are in the 3-step flow.
    private var navigationTitle: String {
        switch viewModel.phase {
        case .setup:     return "1 of 3"
        case .capturing: return "2 of 3"
        case .complete:  return "3 of 3"
        }
    }

    /// Three dots in the nav-bar's principal slot. Filled = current step.
    /// Cheap visual progress indicator — no separate progress bar needed.
    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(index == currentStepIndex ? AppColor.cta : AppColor.border)
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }

    private var currentStepIndex: Int {
        switch viewModel.phase {
        case .setup:     return 0
        case .capturing: return 1
        case .complete:  return 2
        }
    }

    /// Called from Screen 3's "Continue to Rare" CTA. Order matters:
    /// flip the flag FIRST so ContentView's next render is ready, then
    /// dismiss the cover.
    private func finishWizard() {
        state.session.hasSeenLivePreview = true
        dismiss()
    }
}

#Preview {
    // Wrapping in a host view so .fullScreenCover semantics work in the canvas.
    struct PreviewHost: View {
        @State private var showFlow = true
        var body: some View {
            Color.clear.fullScreenCover(isPresented: $showFlow) {
                FirstProductFlowView()
                    .environment(AppState())
            }
        }
    }
    return PreviewHost().preferredColorScheme(.dark)
}
