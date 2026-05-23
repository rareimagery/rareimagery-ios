import SwiftUI
import RareImageryAPI

// MARK: - Onboarding-local color tokens
//
// The repo's design system lives in `Theme/Colors.swift` as
// `enum AppColor` — we use `AppColor.background`, `AppColor.surface`,
// `AppColor.accent`, `AppColor.textPrimary`, `AppColor.textSecondary`,
// and `AppColor.border` throughout this file.
//
// Two extra tokens are onboarding-specific and not yet in `AppColor`.
// If they're reused beyond this flow, promote them into
// `Theme/Colors.swift`.
private extension Color {
    /// #FF6B00 — primary CTA orange (Continue, Retry).
    /// Promote to `AppColor.cta` if reused outside onboarding.
    static let onboardingCTA = Color(red: 255/255, green: 107/255, blue: 0/255)

    /// #1A1A1A — slightly elevated surface for chips inside cards.
    /// Promote to `AppColor.surfaceElevated` if reused.
    static let onboardingSurfaceElevated = Color(red: 26/255, green: 26/255, blue: 26/255)
}

// MARK: - Root

struct OnboardingView: View {
    @State private var viewModel: OnboardingViewModel

    /// Production: pass `state.keychain` from `ContentView` so the API client
    /// can attach the access token to each request.
    @MainActor
    init(keychain: KeychainStore? = nil) {
        _viewModel = State(initialValue: OnboardingViewModel(api: .live(keychain: keychain)))
    }

    /// Test / preview seam — inject a stub view-model.
    @MainActor
    init(viewModel: OnboardingViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack {
            AppColor.background.ignoresSafeArea()

            Group {
                switch viewModel.step {
                case .name:
                    NameInputView(viewModel: viewModel)
                case .building:
                    BuildingView(viewModel: viewModel)
                }
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.28), value: viewModel.step)
    }
}

// MARK: - Step 1 — Name

private struct NameInputView: View {
    @Bindable var viewModel: OnboardingViewModel
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 12) {
                Text("What's your name?")
                    .font(.system(size: 40, weight: .semibold))
                    .tracking(-1.5)
                    .multilineTextAlignment(.center)

                Text("This will be used for your store URL.")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 14) {
                TextField(
                    "",
                    text: Binding(
                        get: { viewModel.name },
                        set: { viewModel.onNameChanged($0) }
                    ),
                    prompt: Text("Your name or brand")
                        .foregroundStyle(.white.opacity(0.4))
                )
                .focused($nameFieldFocused)
                .font(.system(size: 22))
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
                .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 22))
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(borderColor, lineWidth: 1)
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .submitLabel(.go)
                .onSubmit(viewModel.submitName)
                .accessibilityLabel("Your name or brand")

                HandleStatusView(state: viewModel.handleState, storeURL: viewModel.storeURL)

                Button(action: viewModel.submitName) {
                    Text("Continue")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(viewModel.canContinue ? Color.onboardingCTA : Color.onboardingCTA.opacity(0.35))
                        .clipShape(Capsule())
                }
                .disabled(!viewModel.canContinue)
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .onAppear { nameFieldFocused = true }
    }

    private var borderColor: Color {
        switch viewModel.handleState {
        case .available: return .green.opacity(0.7)
        case .taken, .invalid: return .red.opacity(0.7)
        case .checking, .idle: return .white.opacity(0.2)
        }
    }
}

private struct HandleStatusView: View {
    let state: OnboardingViewModel.HandleState
    let storeURL: String

    var body: some View {
        HStack(spacing: 8) {
            icon
            Text(message)
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var icon: some View {
        switch state {
        case .idle:      Image(systemName: "globe").opacity(0.5)
        case .checking:  ProgressView().controlSize(.mini)
        case .available: Image(systemName: "checkmark.circle.fill")
        case .taken:     Image(systemName: "xmark.circle.fill")
        case .invalid:   Image(systemName: "exclamationmark.triangle.fill")
        }
    }

    private var message: String {
        switch state {
        case .idle:                       return storeURL
        case .checking:                   return "Checking \(storeURL)…"
        case .available:                  return "\(storeURL) is available"
        case .taken:                      return "\(storeURL) is taken — try a different name"
        case .invalid(let reason):        return reason
        }
    }

    private var color: Color {
        switch state {
        case .available: return .green
        case .taken, .invalid: return .red
        default: return .white.opacity(0.55)
        }
    }
}

// MARK: - Step 2 — Building

private struct BuildingView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                FollowedUsersBar(viewModel: viewModel)
                YourStoreSection(viewModel: viewModel)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        // Stale-closure fix: drive the circle PUT off view-side state
        // observation, not from inside provisionStore. The view-model
        // debounces internally so we won't fire a PUT per tap.
        .onChange(of: viewModel.storeCreation) { _, _ in
            viewModel.schedulePersistCircle()
        }
        .onChange(of: viewModel.circleSelection) { _, _ in
            viewModel.schedulePersistCircle()
        }
    }
}

private struct FollowedUsersBar: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("People you follow on X")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Tap to add them to your Rare Circle (\(viewModel.circleSelection.count)/24)")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                if !viewModel.followedUsers.isEmpty {
                    Text("\(viewModel.followedUsers.count)")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.1), in: Capsule())
                }
            }

            if viewModel.followedUsers.isEmpty {
                Text("Finding people you follow…")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.vertical, 12)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 160), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(viewModel.followedUsers) { user in
                        FollowedUserChip(
                            user: user,
                            isSelected: viewModel.circleSelection.contains(user.id),
                            action: { viewModel.toggleCircleMember(user) }
                        )
                    }
                }
            }
        }
        .padding(20)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        )
    }
}

private struct FollowedUserChip: View {
    let user: FollowedUser
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                AsyncImage(url: user.avatarURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.white.opacity(0.1)
                }
                .frame(width: 36, height: 36)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text(user.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Text("@\(user.username)")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppColor.accent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.onboardingSurfaceElevated, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? AppColor.accent : .white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(user.name), @\(user.username)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct YourStoreSection: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Text(headline)
                    .font(.system(size: 24, weight: .semibold))
                if case .creating = viewModel.storeCreation {
                    ProgressView().controlSize(.small)
                }
            }

            Text(subhead)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.7))

            Text(viewModel.storeURL)
                .font(.system(size: 18, weight: .medium, design: .monospaced))
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.white.opacity(0.1), lineWidth: 1)
                )
                .opacity(isStoreReady ? 1.0 : 0.7)

            if case .failed(let message) = viewModel.storeCreation {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Store creation failed: \(message)")
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                    Button("Retry", action: viewModel.retryProvisioning)
                        .buttonStyle(.borderedProminent)
                        .tint(Color.onboardingCTA)
                        .foregroundStyle(.black)
                }
            }

            if case .ready = viewModel.storeCreation {
                productKindPicker
            }
        }
        .padding(24)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        )
    }

    private var isStoreReady: Bool {
        if case .ready = viewModel.storeCreation { return true }
        return false
    }

    private var headline: String {
        switch viewModel.storeCreation {
        case .creating, .idle: return "Your store is being created"
        case .ready:           return "Your store is ready"
        case .failed:          return "Something went wrong"
        }
    }

    private var subhead: String {
        switch viewModel.storeCreation {
        case .creating, .idle: return "Setting up your store on Rare…"
        case .ready:           return "Live at"
        case .failed:          return "We hit an error while provisioning. Try again below."
        }
    }

    @ViewBuilder private var productKindPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What do you want to sell first?")
                .font(.system(size: 16, weight: .medium))

            HStack(spacing: 10) {
                productKindCard(
                    title: "Physical merch",
                    subtitle: "Tees, hoodies, posters, etc.",
                    kind: "physical"
                )
                productKindCard(
                    title: "Digital products",
                    subtitle: "Downloads, templates, files",
                    kind: "digital"
                )
            }
        }
    }

    private func productKindCard(title: String, subtitle: String, kind: String) -> some View {
        Button {
            // TODO: route into design-studio with the picked kind.
            // Match the web flow: /design-studio?kind=<kind>&store=<slug>
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(Color.onboardingSurfaceElevated, in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(.white.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }
}

// MARK: - Preview

#Preview("Onboarding (preview API)") {
    OnboardingView(viewModel: OnboardingViewModel(api: .preview))
}
