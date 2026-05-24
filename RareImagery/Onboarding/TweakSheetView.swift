import SwiftUI
import RareImageryAPI

/// Optional store-refinement sheet. Presented from LivePreviewView when
/// the user taps "Tweak my store first." Single pane — preview at top,
/// tweakers below. Not a multi-step wizard; everything visible at once.
///
/// User changes color / bio / slug, watches the preview update live,
/// taps "Save & continue" → PATCHes their x_profile via
/// /api/v1/creator/provision-store, sheet dismisses, parent
/// LivePreviewView re-renders with the saved state.
///
/// Voice: still Rare-led but less mascot-heavy than the welcome screens.
/// User is in "configure" mode now; copy is more direct.
///
/// What's intentionally NOT in this sheet (deferred to Console):
///   - Featured posts picker — needs the X-feed fetcher which is a
///     separate iOS surface
///   - Friends/favorites picker — uses /api/social/circle/suggestions
///     which deserves a dedicated screen
///   - Template picker — only 3 templates; default 'modern-cart' works
///     for v1 of mobile onboarding
///
/// These can be tweaked from Console after creator's first product
/// publishes. The 60-second story is: sign-in → tweak briefly →
/// capture → publish.
struct TweakSheetView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var selectedColor: LiveStorePreview.ColorSchemeOption = .default
    @State private var bioOverride: String = ""
    @State private var slugDraft: String = ""
    @State private var slugStatus: SlugStatus = .idle
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var slugCheckTask: Task<Void, Never>?

    enum SlugStatus: Equatable {
        case idle
        case checking
        case available
        case taken
        case invalid(reason: String)

        var isReady: Bool { self == .available || self == .idle }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Mini preview — same component as LivePreviewView,
                        // bound to local state so it updates as user tweaks
                        LiveStorePreview(
                            displayName: state.session.displayHandle ?? "your name",
                            handle: state.session.claims?.handle ?? "yourname",
                            bio: bioOverride.isEmpty ? "" : bioOverride,
                            avatarURL: avatarURLFromClaims,
                            bannerURL: nil,
                            colorScheme: selectedColor,
                            slug: slugDraft.isEmpty ? (state.session.claims?.slug ?? "yourname") : slugDraft
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                        // Color picker
                        sectionCard(title: "Pick a vibe") {
                            colorPickerGrid
                        }

                        // Bio override
                        sectionCard(title: "Add a tagline") {
                            TextField(
                                "Something memorable. We pulled your X bio if you have one.",
                                text: $bioOverride,
                                axis: .vertical
                            )
                            .lineLimit(2...4)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(AppColor.background, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColor.border, lineWidth: 1))
                            .foregroundStyle(AppColor.textPrimary)
                        }

                        // Slug rename
                        sectionCard(title: "Your store URL") {
                            slugSection
                        }

                        // Save CTA
                        saveButton

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red.opacity(0.9))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                    }
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Make it yours")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
            .preferredColorScheme(.dark)
            .onAppear { prefillFromClaims() }
        }
    }

    // MARK: Section helpers

    @ViewBuilder
    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColor.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)
            content()
        }
        .padding(16)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 20)
    }

    private var colorPickerGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 60), spacing: 12)],
            spacing: 12
        ) {
            ForEach(LiveStorePreview.ColorSchemeOption.all) { option in
                Button {
                    selectedColor = option
                } label: {
                    VStack(spacing: 4) {
                        Circle()
                            .fill(option.accentColor)
                            .frame(width: 40, height: 40)
                            .overlay(
                                Circle()
                                    .stroke(
                                        selectedColor.id == option.id ? AppColor.textPrimary : Color.clear,
                                        lineWidth: 2
                                    )
                                    .padding(-3)
                            )
                        Text(option.label)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(
                                selectedColor.id == option.id ? AppColor.textPrimary : AppColor.textSecondary
                            )
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var slugSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                TextField("yourname", text: $slugDraft)
                    .textFieldStyle(.plain)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .onChange(of: slugDraft) { _, newValue in
                        onSlugChange(newValue)
                    }
                    .padding(12)
                    .background(AppColor.background, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(slugBorderColor, lineWidth: 1))
                    .foregroundStyle(AppColor.textPrimary)

                Text(".rareimagery.net")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(AppColor.textSecondary)
            }

            HStack(spacing: 6) {
                slugStatusIcon
                Text(slugStatusMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(slugStatusColor)
            }
        }
    }

    @ViewBuilder
    private var slugStatusIcon: some View {
        switch slugStatus {
        case .idle:
            Image(systemName: "globe").opacity(0.5)
        case .checking:
            ProgressView().controlSize(.mini)
        case .available:
            Image(systemName: "checkmark.circle.fill")
        case .taken, .invalid:
            Image(systemName: "xmark.circle.fill")
        }
    }

    private var slugStatusMessage: String {
        switch slugStatus {
        case .idle:
            return slugDraft.isEmpty ? "Keep your current URL" : "\(slugDraft).rareimagery.net"
        case .checking:
            return "Checking…"
        case .available:
            return "Available"
        case .taken:
            return "Already taken — try a different name"
        case .invalid(let reason):
            return reason
        }
    }

    private var slugStatusColor: Color {
        switch slugStatus {
        case .available: return .green
        case .taken, .invalid: return .red
        default: return AppColor.textSecondary
        }
    }

    private var slugBorderColor: Color {
        switch slugStatus {
        case .available: return .green.opacity(0.6)
        case .taken, .invalid: return .red.opacity(0.6)
        default: return AppColor.border
        }
    }

    private var saveButton: some View {
        Button(action: { Task { await save() } }) {
            HStack {
                if isSaving {
                    ProgressView().tint(.black)
                }
                Text(isSaving ? "Saving…" : "Save & continue")
                    .font(.system(size: 17, weight: .semibold))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(canSave ? AppColor.cta : AppColor.cta.opacity(0.4))
            .clipShape(Capsule())
        }
        .disabled(!canSave)
        .padding(.horizontal, 20)
    }

    private var canSave: Bool {
        !isSaving && slugStatus.isReady
    }

    // MARK: Actions

    private func prefillFromClaims() {
        // Color defaults to midnight (matches Drupal default for field_color_scheme)
        // Bio + slug stay empty so we show the "use the current value" affordance
        // unless the user explicitly edits.
    }

    private func onSlugChange(_ raw: String) {
        slugCheckTask?.cancel()

        // Local format check first — same rules as src/lib/reserved-subdomains.ts client side
        let trimmed = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            slugStatus = .idle
            return
        }
        if trimmed.count < 3 || trimmed.count > 30 {
            slugStatus = .invalid(reason: "Must be 3–30 characters")
            return
        }
        if trimmed.range(of: "^[a-z0-9-]+$", options: .regularExpression) == nil {
            slugStatus = .invalid(reason: "Only lowercase letters, numbers, hyphens")
            return
        }
        if trimmed.hasPrefix("-") || trimmed.hasSuffix("-") {
            slugStatus = .invalid(reason: "Can't start or end with a hyphen")
            return
        }

        slugStatus = .checking
        slugCheckTask = Task {
            // Debounce 300ms
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }

            // Live check against /api/v1/stores/check-slug
            // (Bearer auth via the existing APIClient on AppState)
            do {
                let available = try await checkSlugRemote(trimmed)
                guard !Task.isCancelled else { return }
                slugStatus = available ? .available : .taken
            } catch {
                // Network error → optimistic-available so user isn't blocked.
                // Drupal does the authoritative check at provision time anyway.
                guard !Task.isCancelled else { return }
                slugStatus = .available
            }
        }
    }

    /// Hits /api/v1/stores/check-slug via the configured APIClient.
    /// The BFF handler uses requireSessionOrMobile so the iOS Bearer JWT
    /// works (verified Round 9 — returns 401 unauthenticated, 200 with
    /// { available, reason? } shape when authenticated).
    private func checkSlugRemote(_ slug: String) async throws -> Bool {
        // TODO: wire to the actual APIClient method once the iOS-side
        // CheckSlugRepository.checkAvailability(slug:) helper exists.
        // For now, optimistically return true so the UX flows; the real
        // call lands in a follow-up PR (Issue #14 iOS smoke).
        try await Task.sleep(for: .milliseconds(200))
        return true
    }

    private func save() async {
        guard canSave else { return }
        isSaving = true
        errorMessage = nil

        // TODO: wire to actual provision-store PATCH endpoint when the
        // iOS-side OnboardingRepository.updateStore(...) helper exists.
        // For now: simulate the save + dismiss so the UX flow is testable.
        //
        // Expected real call:
        //   try await state.onboardingRepository.updateStore(
        //     slug: slugDraft.isEmpty ? nil : slugDraft,
        //     colorScheme: selectedColor.id,
        //     bio: bioOverride.isEmpty ? nil : bioOverride
        //   )
        // On success, ContentView re-renders with the new state.

        try? await Task.sleep(for: .milliseconds(600))

        isSaving = false
        dismiss()
    }

    private var avatarURLFromClaims: URL? {
        guard let url = state.session.creator?.avatarUrl, !url.isEmpty else {
            return nil
        }
        return URL(string: url)
    }
}

#Preview {
    TweakSheetView()
        .environment(AppState())
        .preferredColorScheme(.dark)
}
