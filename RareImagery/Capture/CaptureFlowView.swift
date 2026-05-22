import SwiftUI
import RareImageryAPI

struct CaptureFlowView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ZStack {
            CaptureView()

            switch state.capture.phase {
            case .uploading(let completed, let total):
                overlay(title: "Uploading", subtitle: "\(completed) of \(total)")
            case .analyzing:
                overlay(title: "Analyzing", subtitle: "Grok Vision is reading the photo")
            case .ready(let draft):
                DraftPreview(draft: draft)
            case .error(let message):
                errorBanner(message: message)
            case .idle, .picking:
                EmptyView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Sign out") {
                    Task { await state.signOut() }
                }
                .foregroundStyle(AppColor.textSecondary)
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
                if let description = draft.description {
                    Text(description)
                        .font(AppFont.body)
                        .foregroundStyle(AppColor.textSecondary)
                }
                HStack(spacing: 8) {
                    if let cat = draft.category {
                        labelChip(cat.displayName)
                    }
                    if let cond = draft.condition {
                        labelChip(cond.displayName)
                    }
                    if let price = draft.suggestedPrice {
                        labelChip("$\(price)")
                    }
                }
                if let tags = draft.tags, !tags.isEmpty {
                    Text(tags.map { "#\($0)" }.joined(separator: " "))
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

/// Static helper that runs the upload + analyze pipeline.
/// Lives at top-level so views can call it without holding a reference to a view-model.
@MainActor
enum CaptureCoordinator {
    static func run(state: AppState) async {
        let capture = state.capture
        let upload = state.uploadRepository
        let products = state.productRepository

        guard capture.canAnalyze else { return }

        let total = capture.shots.count
        capture.phase = .uploading(completed: 0, total: total)

        for (i, shot) in capture.shots.enumerated() where shot.uploadedURL == nil {
            do {
                let resp = try await upload.upload(jpegData: shot.jpegData, filename: "shot-\(i + 1).jpg")
                if let url = resp.publicURL {
                    capture.markUploaded(id: shot.id, url: url)
                }
                capture.phase = .uploading(completed: i + 1, total: total)
            } catch {
                capture.phase = .error("Upload failed (\(i + 1)/\(total)): \(message(error))")
                return
            }
        }

        guard let hero = capture.hero, let heroURL = hero.uploadedURL else {
            capture.phase = .error("Hero image has no upload URL.")
            return
        }

        let extras = capture.shots
            .filter { $0.id != hero.id }
            .compactMap(\.uploadedURL)

        capture.phase = .analyzing
        do {
            let draft = try await products.fromImages(
                heroURL: heroURL,
                additionalURLs: extras,
                voiceTranscript: capture.voiceTranscript.isEmpty ? nil : capture.voiceTranscript,
                intent: capture.intent,
                storeUuid: state.session.claims?.storeUuid
            )
            capture.phase = .ready(draft)
        } catch {
            capture.phase = .error("Analyze failed: \(message(error))")
        }
    }

    private static func message(_ error: Error) -> String {
        if let api = error as? APIError {
            switch api {
            case .unauthorized: return "Unauthorized"
            case .badRequest(let m): return m
            case .serverError(_, let m): return m ?? "Server error"
            case .network: return "Network unreachable"
            case .decode(let m): return "Decode: \(m)"
            default: return "\(api)"
            }
        }
        return error.localizedDescription
    }
}
