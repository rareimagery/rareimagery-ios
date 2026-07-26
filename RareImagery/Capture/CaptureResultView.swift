import SwiftUI
import RareImageryAPI

/// Post-analysis screen. Shows the user what Rare saw — the analyzed
/// product draft from `POST /api/vision/analyze` — and the three real
/// actions:
///
///   1. Primary  — "Make this sellable" → opens QuickProductView
///   2. Secondary — "Capture another" → returns to camera, keeps this
///      draft in-session
///   3. Tertiary — "Save & close" → keeps draft in session, dismisses
///
/// Voice: Rare reports what he saw. "What Rare saw" navigation title
/// is mascot-first; the three actions read as conversation continuations,
/// not feature buttons.
///
/// Wiring:
///   - `CaptureSession.phase` should be `.ready(ProductDraft)` when this
///     view is presented. If the parent presents it any earlier the
///     fallback copy keeps the layout from collapsing.
///   - "Make sellable" presents `QuickProductView` as a sheet —
///     QuickProductView is the form that posts to the backend.
struct CaptureResultView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var showQuickProduct = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        heroImage
                        analysisCard

                        Spacer(minLength: 32)

                        actionStack
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("What Rare saw")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(AppColor.textPrimary)
                }
            }
            .sheet(isPresented: $showQuickProduct) {
                if let draft = currentDraft {
                    QuickProductView(draft: draft, heroImageData: state.capture.hero?.jpegData)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Sections

    @ViewBuilder private var heroImage: some View {
        if let data = state.capture.hero?.jpegData,
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 320)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else {
            // Should be rare in practice — parent shouldn't push without a hero.
            RoundedRectangle(cornerRadius: 20)
                .fill(AppColor.surface)
                .frame(height: 240)
                .overlay {
                    Image(systemName: "photo")
                        .font(.title)
                        .foregroundStyle(AppColor.textSecondary)
                }
        }
    }

    @ViewBuilder private var analysisCard: some View {
        if let draft = currentDraft {
            VStack(alignment: .leading, spacing: 12) {
                Text(draft.title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(AppColor.textPrimary)

                if let summary = draft.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 15))
                        .foregroundStyle(AppColor.textSecondary)
                        .lineSpacing(3)
                }

                if let price = draft.priceDisplay {
                    HStack(spacing: 6) {
                        Image(systemName: "tag.fill")
                            .font(.caption)
                        Text(price)
                            .font(.system(size: 15, weight: .medium))
                    }
                    .foregroundStyle(AppColor.cta)
                    .padding(.top, 4)
                }

                if let tags = draft.tags, !tags.isEmpty {
                    TagChips(tags: tags)
                        .padding(.top, 4)
                }
            }
            .padding(20)
            .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 16))
        } else {
            // Phase != .ready(draft) — show a soft "still working" fallback
            // rather than crash on missing data.
            HStack(spacing: 12) {
                ProgressView()
                    .tint(AppColor.textSecondary)
                Text("Rare's still thinking…")
                    .font(.system(size: 15))
                    .foregroundStyle(AppColor.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    @ViewBuilder private var actionStack: some View {
        VStack(spacing: 12) {
            Button {
                showQuickProduct = true
            } label: {
                Text("Make this sellable")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(AppColor.cta)
                    .clipShape(Capsule())
            }
            .disabled(currentDraft == nil)

            Button {
                state.capture.reset()
                dismiss()
            } label: {
                Text("Capture another")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppColor.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppColor.surface)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(AppColor.border, lineWidth: 1))
            }

            Button {
                // Drafts persistence is out of scope for this PR — current
                // CaptureSession only holds the active draft. "Save" here is
                // effectively the same as "Done" until a SwiftData backing
                // model lands. See README follow-up.
                dismiss()
            } label: {
                Text("Save & close")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColor.textSecondary)
                    .padding(.vertical, 8)
            }
        }
    }

    private var currentDraft: ProductDraft? {
        if case .ready(_, let draft) = state.capture.phase {
            return draft
        }
        return nil
    }
}

/// Small chip-row for analysis tags. Adaptive grid so 1–N tags wrap cleanly.
private struct TagChips: View {
    let tags: [String]

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 70), spacing: 8)],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppColor.background, in: Capsule())
                    .foregroundStyle(AppColor.textSecondary)
                    .overlay(Capsule().stroke(AppColor.border, lineWidth: 1))
            }
        }
    }
}

#Preview {
    CaptureResultView()
        .environment(AppState())
        .preferredColorScheme(.dark)
}
