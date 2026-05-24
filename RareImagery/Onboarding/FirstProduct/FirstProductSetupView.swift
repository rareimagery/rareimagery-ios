import SwiftUI
import RareImageryAPI

/// Screen 1 of the first-product wizard. Avatar + greeting header,
/// followed by two chip-based questions (product type — multi-select,
/// style — single-select), and a primary CTA to advance to capture.
///
/// Header style intentionally simpler than `LiveStorePreview` — the
/// wizard is focused on a single task (make a product), not on
/// re-validating "your store is real" (that's LivePreviewView's job).
struct FirstProductSetupView: View {
    @Environment(AppState.self) private var state
    @Bindable var viewModel: FirstProductViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                    .padding(.top, 8)

                heroCopy

                QuestionCard("What kind of products do you want to sell most?") {
                    FlowLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(FirstProductViewModel.productTypeOptions, id: \.self) { type in
                            Chip(
                                title: type,
                                isSelected: viewModel.selectedProductTypes.contains(type),
                                action: { viewModel.toggleProductType(type) }
                            )
                        }
                    }
                }

                QuestionCard("What's your main vibe or style?") {
                    FlowLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(FirstProductViewModel.styleOptions, id: \.self) { style in
                            Chip(
                                title: style,
                                isSelected: viewModel.selectedStyle == style,
                                action: { viewModel.selectStyle(style) }
                            )
                        }
                    }
                }

                continueButton

                Spacer().frame(height: 24)
            }
            .padding(.horizontal, 20)
        }
        .background(AppColor.background)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 14) {
            // Banner gradient + avatar in front. Mirrors LiveStorePreview's
            // header rhythm but stripped down — no display name / handle /
            // bio block here because the user already confirmed all that
            // on LivePreviewView one tap ago.
            ZStack(alignment: .bottom) {
                LinearGradient(
                    colors: [AppColor.accent.opacity(0.45), AppColor.cta.opacity(0.35)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                avatarCircle
                    .offset(y: 34)
            }
            .padding(.bottom, 34) // claw back avatar offset

            if let handle = state.session.displayHandle, !handle.isEmpty {
                Text("Hi, @\(handle)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
    }

    private var avatarCircle: some View {
        Group {
            if let url = avatarURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        placeholderAvatar
                    }
                }
            } else {
                placeholderAvatar
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(Circle())
        .overlay(Circle().stroke(AppColor.background, lineWidth: 3))
    }

    private var placeholderAvatar: some View {
        Circle()
            .fill(AppColor.surface)
            .overlay(
                Image(systemName: "person.fill")
                    .foregroundStyle(AppColor.textSecondary)
            )
    }

    private var heroCopy: some View {
        VStack(spacing: 8) {
            Text("Make your first thing")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)

            Text("Two quick questions, then we'll go to the camera.")
                .font(.system(size: 15))
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .padding(.horizontal, 24)
    }

    private var continueButton: some View {
        Button {
            viewModel.advanceToCapture()
        } label: {
            HStack(spacing: 8) {
                Text("Continue to create your first product")
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

    // MARK: - Helpers

    /// Avatar URL is surfaced on the post-sign-in `AuthTokenResponse.creator`
    /// — same path LivePreviewView uses. nil when the X profile hasn't
    /// been hydrated yet (we render the placeholder).
    private var avatarURL: URL? {
        guard let raw = state.session.creator?.avatarUrl, !raw.isEmpty else {
            return nil
        }
        return URL(string: raw)
    }
}

#Preview {
    FirstProductSetupView(viewModel: FirstProductViewModel())
        .environment(AppState())
        .preferredColorScheme(.dark)
}
