import SwiftUI

/// Big bottom CTA — provisions the store + publishes the product +
/// (optionally) sends to Circle. Different label per phase:
///   .idle / .ideasReady    → "Pick an idea to continue"   (disabled)
///   .previewReady          → "Create my shirt + launch store"
///   .publishing            → "Launching…"                  (spinner)
///   .published             → "View my store"
struct CreateAndLaunchButton: View {
    enum State {
        case waitingForIdea
        case waitingForPreview
        case readyToCreate(productLabel: String)
        case publishing
        case published
    }

    let state: State
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView().tint(.black)
                }
                Text(label)
                    .font(.system(size: 17, weight: .semibold))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(background, in: Capsule())
            .shadow(color: AppColor.cta.opacity(isEnabled ? 0.35 : 0), radius: 18, y: 8)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
        .accessibilityLabel(label)
    }

    private var label: String {
        switch state {
        case .waitingForIdea:                  return "Pick an idea to continue"
        case .waitingForPreview:               return "Generating preview…"
        case .readyToCreate(let productLabel): return "Create my \(productLabel.lowercased()) + launch store"
        case .publishing:                      return "Launching…"
        case .published:                       return "View my store"
        }
    }

    private var background: Color {
        isEnabled ? AppColor.cta : AppColor.cta.opacity(0.35)
    }

    private var isEnabled: Bool {
        switch state {
        case .waitingForIdea, .waitingForPreview, .publishing: return false
        default: return true
        }
    }

    private var isLoading: Bool {
        switch state {
        case .publishing, .waitingForPreview: return true
        default: return false
        }
    }
}
