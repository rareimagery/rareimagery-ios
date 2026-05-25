import SwiftUI
import RareImageryAPI

struct CaptureFlowView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ZStack {
            CaptureView()

            switch state.capture.phase {
            case .working:
                overlay(title: "Analyzing", subtitle: "Reading your hero shot")
            case .ready(let draft):
                DraftPreview(draft: draft)
            case .error(let message):
                errorBanner(message: message)
            case .idle, .picking:
                EmptyView()
            }
        }
    }

    private func overlay(title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(AppColor.accent)
                .controlSize(.large)
            Text(title).font(AppFont.title).foregroundStyle(AppColor.textPrimary)
            Text(subtitle).font(AppFont.callout).foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.background.opacity(0.92))
    }

    private func errorBanner(message: String) -> some View {
        VStack {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.orange)
                Text(message)
                    .font(AppFont.callout)
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.center)
                Button("Dismiss") {
                    state.capture.phase = .idle
                }
                .padding(.top, 4)
                .tint(AppColor.accent)
            }
            .padding(20)
            .background(AppColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }
}

private struct DraftPreview: View {
    let draft: ProductDraft
    @Environment(AppState.self) private var state

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(draft.title)
                    .font(AppFont.title)
                    .foregroundStyle(AppColor.textPrimary)

                if let summary = draft.summary {
                    Text(summary)
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary.opacity(0.9))
                }

                if let description = draft.description {
                    Text(description)
                        .font(AppFont.body)
                        .foregroundStyle(AppColor.textSecondary)
                }

                HStack(spacing: 8) {
                    if let cat = draft.category { labelChip(cat.displayName) }
                    if let cond = draft.condition { labelChip(cond.displayName) }
                    if let brand = draft.brand { labelChip(brand) }
                    if let price = draft.priceDisplay { labelChip(price) }
                    if draft.handmade == true { labelChip("Handmade") }
                }

                if let tags = draft.tags, !tags.isEmpty {
                    Text(tags.map { "#\($0)" }.joined(separator: " "))
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }

                if let flags = draft.flags, !flags.isEmpty {
                    Text("Flags: \(flags.joined(separator: ", "))")
                        .font(AppFont.caption)
                        .foregroundStyle(.orange)
                }

                if let conf = draft.confidence {
                    Text("Confidence: \(Int((conf * 100).rounded()))%")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }

                Spacer(minLength: 24)
                Button("New capture") {
                    state.capture.reset()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColor.accent)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppColor.background)
    }

    private func labelChip(_ text: String) -> some View {
        Text(text)
            .font(AppFont.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AppColor.surface)
            .clipShape(Capsule())
            .foregroundStyle(AppColor.textPrimary)
    }
}

/// Drives the `/api/vision/analyze` call. JSON + base64 data URLs.
/// Each shot is pre-compressed to ≤1280px JPEG 0.85 before encoding.
@MainActor
enum CaptureCoordinator {
    static func run(state: AppState) async {
        let capture = state.capture
        let products = state.productRepository

        guard capture.canAnalyze else { return }
        capture.phase = .working

        // Move hero to front so `heroOnly: true` semantics match user intent.
        let orderedShots: [CaptureSession.Shot] = {
            guard capture.shots.indices.contains(capture.heroIndex) else { return capture.shots }
            var rest = capture.shots
            let hero = rest.remove(at: capture.heroIndex)
            return [hero] + rest
        }()

        let dataURLs = orderedShots.map { ImageCompression.toBase64DataURL($0.jpegData) }

        do {
            let result = try await products.analyze(
                dataURLs: dataURLs,
                intent: capture.intent,
                voiceTranscript: capture.voiceTranscript.isEmpty ? nil : capture.voiceTranscript,
                heroOnly: true
            )
            capture.phase = .ready(result.draft)
        } catch {
            capture.phase = .error(message(error))
        }
    }

    private static func message(_ error: Error) -> String {
        if let api = error as? APIError { return api.userFacingMessage }
        return error.localizedDescription
    }
}
