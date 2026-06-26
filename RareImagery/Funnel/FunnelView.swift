import SwiftUI
import RareImageryAPI

/// Value-first pre-login **Video Submission Flow** — Instructions → Record →
/// Processing → Result. Design source:
/// `~/rareimagery-brain/memory/design/video-submission-flow.dc.html`.
///
/// Phase 2: full UI + state machine with a **mock** recorder + valuation.
/// Phase 3 swaps real AVFoundation capture; Phase 5 swaps the real
/// `from-video` valuation. The account wall sits on the Result CTA.
struct VideoSubmissionFunnelView: View {
    @State private var vm = FunnelViewModel()
    @Environment(AppState.self) private var state

    var body: some View {
        ZStack {
            switch vm.screen {
            case .instructions: FunnelInstructionsView(vm: vm)
            case .record, .recording: FunnelRecordView(vm: vm)
            case .processing: FunnelProcessingView(vm: vm)
            case .result: FunnelResultView(vm: vm)
            }
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.25), value: vm.screen)
        .task {
            vm.appState = state
            await vm.prepareCamera()
        }
    }
}

/// Local valuation model for the funnel result/hook screen. Mirrors the design's
/// fields (incl. rarity + insights, which the shared `ProductDraft` doesn't carry
/// yet). Phase 5 maps the real `/api/products/from-video` response into this.
struct FunnelValuation: Equatable {
    var title: String
    var valueLow: Int
    var valueHigh: Int
    var suggested: Int
    var category: String
    var condition: String
    var rarity: Double      // 0–10
    var confidence: Int     // 0–100
    var insights: [String]

    static let mock = FunnelValuation(
        title: "Vintage Leather Moto Jacket",
        valueLow: 120, valueHigh: 180, suggested: 149,
        category: "Apparel · Outerwear", condition: "Good",
        rarity: 7.4, confidence: 92,
        insights: [
            "Genuine leather, late-80s cut — desirable with collectors.",
            "Minor wear at cuffs reads as patina, not damage.",
            "Best sold as a limited drop — Edition № 001 / 001.",
        ]
    )
}

@MainActor @Observable
final class FunnelViewModel {
    enum Screen: Equatable { case instructions, record, recording, processing, result }

    var screen: Screen = .instructions
    var seconds = 0
    var promptIndex = 0
    var valuation: FunnelValuation?
    var errorMessage: String?
    var appState: AppState?
    let capture = VideoCaptureService()

    let prompts = ["What is it?", "How old is it?", "Any flaws or wear?",
                   "What makes it rare?", "Where's it from?"]

    private var ticker: Task<Void, Never>?

    var timeLabel: String { String(format: "%02d:%02d", seconds / 60, seconds % 60) }
    var currentPrompt: String { prompts[promptIndex % prompts.count] }

    func openCamera() { screen = .record }

    /// Camera + mic permission, then start the AVCaptureSession. Call on appear.
    func prepareCamera() async {
        if await capture.requestPermissions() {
            await capture.configureIfNeeded()
        } else {
            errorMessage = "Camera & microphone access are needed to record."
        }
    }

    func startRecording() {
        seconds = 0; promptIndex = 0; screen = .recording
        capture.startRecording()
        ticker = Task { [weak self] in
            var elapsed = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                elapsed += 1
                self.seconds = elapsed
                if elapsed % 3 == 0 { self.promptIndex += 1 }
            }
        }
    }

    func stopRecording() {
        ticker?.cancel(); ticker = nil
        screen = .processing
        Task { [weak self] in
            guard let self else { return }
            let url = await self.capture.stopRecording()
            await self.process(clip: url)
        }
    }

    /// On-device reduction + valuation (hybrid). Frames + transcript are always
    /// produced here (the Grok-independent work); the valuation is mocked while
    /// `useMocks` is on, real otherwise. Raw-clip upload is fired async + gated.
    private func process(clip url: URL?) async {
        var frames: [String] = []
        var transcript: String?
        if let url {
            frames = await FrameSelector.selectFrames(from: url, maxCount: 4)
            transcript = await SpeechService.transcribe(url: url)
        }

        if let appState, !appState.useMocks, !frames.isEmpty {
            do {
                let result = try await appState.productRepository.analyze(
                    dataURLs: frames, intent: .resell,
                    voiceTranscript: transcript, heroOnly: false, source: "video"
                )
                valuation = FunnelValuation(from: result.draft)
            } catch {
                errorMessage = String(describing: error)
                valuation = .mock
            }
            if let url {  // raw-clip retention (CAPTURE-CONTRACT §4) — async, never blocks
                Task { [appState] in _ = try? await appState.videoUploadRepository.upload(fileURL: url) }
            }
        } else {
            try? await Task.sleep(for: .seconds(0.6))   // stubbed valuation (useMocks)
            valuation = .mock
        }
        screen = .result
    }

    func reset() {
        ticker?.cancel(); ticker = nil
        seconds = 0; promptIndex = 0; valuation = nil; screen = .record
    }
}

// MARK: - Shared funnel chrome

/// "Rare." wordmark with the foil-gold period.
struct RareWordmark: View {
    var size: CGFloat = 19
    var body: some View {
        HStack(spacing: 0) {
            Text("Rare").foregroundStyle(.white)
            Text(".").foregroundStyle(AppColor.foil)
        }
        .font(AppFont.mono(size, .bold))
    }
}

/// Full-width gold CTA (the design's primary action).
struct FunnelGoldButton: View {
    let title: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppFont.buttonLabel)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(AppColor.gold, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

extension FunnelValuation {
    /// Maps a backend `ProductDraft` → funnel valuation. `rarity`, `insights`, and a
    /// single `suggestedPrice` aren't in `ProductDraft` yet (CAPTURE-CONTRACT.md §5.1) —
    /// placeholders until the backend adds them.
    init(from draft: ProductDraft) {
        let low = draft.suggestedPriceLow.map { NSDecimalNumber(decimal: $0).intValue } ?? 0
        let high = draft.suggestedPriceHigh.map { NSDecimalNumber(decimal: $0).intValue } ?? low
        self.init(
            title: draft.title,
            valueLow: low,
            valueHigh: high,
            suggested: high > 0 ? (low + high) / 2 : low,
            category: draft.category?.displayName ?? "—",
            condition: draft.condition?.displayName ?? "—",
            rarity: 0,
            confidence: Int(((draft.confidence ?? 0) * 100).rounded()),
            insights: draft.tags ?? []
        )
    }
}
