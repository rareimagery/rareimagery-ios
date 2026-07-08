import SwiftUI
import OSLog
import RareImageryAPI

/// Value-first pre-login **Video Submission Flow** — Instructions → Record →
/// Processing → Result. Design source:
/// `~/rareimagery-brain/memory/design/video-submission-flow.dc.html`.
///
/// Phase 2: full UI + state machine with a **mock** recorder + valuation.
/// Phase 3 swaps real AVFoundation capture; Phase 5 swaps the real
/// `from-video` valuation. The account wall sits on the Result CTA.
struct VideoSubmissionFunnelView: View {
    var onExit: (() -> Void)? = nil
    /// `true` when reused as the signed-in "Create a product" flow: the
    /// value call is authenticated (BFF binds the draft to the creator),
    /// and the result CTA becomes "Add to store" instead of "Claim with X".
    var productMode: Bool = false
    /// Product mode: called by the result screen's "Add to store" so the
    /// host can close the flow AND land the user on the Products screen
    /// (where the new draft shows as UNPUBLISHED). Falls back to onExit.
    var onProductAdded: (() -> Void)? = nil
    @State private var vm = FunnelViewModel()
    @Environment(AppState.self) private var state

    var body: some View {
        ZStack {
            switch vm.screen {
            case .instructions: FunnelInstructionsView(vm: vm, onExit: onExit)
            case .record, .recording: FunnelRecordView(vm: vm)
            case .processing: FunnelProcessingView(vm: vm)
            case .result: FunnelResultView(vm: vm, onExit: onExit)
            }
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.25), value: vm.screen)
        .task {
            vm.appState = state
            vm.productMode = productMode
            vm.onProductAdded = onProductAdded
            await vm.prepareCamera()
        }
    }
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
    /// Set by VideoSubmissionFunnelView when used for signed-in product
    /// creation (authenticated value call + "Add to store" result CTA).
    var productMode = false
    /// Product mode: "Add to store" handler (close + show Products screen).
    var onProductAdded: (() -> Void)?
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
    ///
    /// Real path calls the ANONYMOUS `POST /api/v1/vision/value` endpoint
    /// (no bearer token — the funnel runs before any session exists), not
    /// the authenticated `/api/vision/analyze` used by product-mode capture.
    /// See `ProductRepository.valueAnonymously`.
    private func process(clip url: URL?) async {
        var frames: [String] = []
        var transcript: String?
        if let url {
            frames = await FrameSelector.selectFrames(from: url, maxCount: 4)
            transcript = await SpeechService.transcribe(url: url)
        }

        if let appState, !appState.useMocks, !frames.isEmpty {
            var draftUuidForClip: String?
            do {
                let deviceId = try await appState.keychain.stableDeviceId()
                let result = try await appState.productRepository.valueAnonymously(
                    dataURLs: frames,
                    voiceTranscript: transcript,
                    deviceId: deviceId,
                    source: "video",
                    // Signed-in product creation → authenticated call so the
                    // BFF binds the draft to the creator (owned product).
                    authenticated: productMode && appState.session.isSignedIn
                )
                if let uuid = result.draftUuid {
                    // In product mode the draft is already owned; otherwise
                    // it's the pending draft claimed at sign-in.
                    try? await appState.keychain.set(uuid, for: .pendingDraftUuid)
                }
                draftUuidForClip = result.draftUuid
                valuation = FunnelValuation(from: result.draft)
            } catch {
                errorMessage = String(describing: error)
                os_log(.error, "funnel valuation failed: %{public}@", String(describing: error))
                valuation = .mock
            }
            if let url {  // capture-clip upload — async, never blocks. draftUuid (when
                // known) links it to the product as the detail-page video; without
                // one it's private retention (CAPTURE-CONTRACT §4).
                Task { [appState] in _ = try? await appState.videoUploadRepository.upload(fileURL: url, draftUuid: draftUuidForClip) }
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


