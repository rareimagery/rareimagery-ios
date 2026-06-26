import SwiftUI

/// Value-first pre-login **Video Submission Flow** — Instructions → Record →
/// Processing → Result. Design source:
/// `~/rareimagery-brain/memory/design/video-submission-flow.dc.html`.
///
/// Phase 2: full UI + state machine with a **mock** recorder + valuation.
/// Phase 3 swaps real AVFoundation capture; Phase 5 swaps the real
/// `from-video` valuation. The account wall sits on the Result CTA.
struct VideoSubmissionFunnelView: View {
    @State private var vm = FunnelViewModel()

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

    let prompts = ["What is it?", "How old is it?", "Any flaws or wear?",
                   "What makes it rare?", "Where's it from?"]

    private var ticker: Task<Void, Never>?

    var timeLabel: String { String(format: "%02d:%02d", seconds / 60, seconds % 60) }
    var currentPrompt: String { prompts[promptIndex % prompts.count] }

    func openCamera() { screen = .record }

    func startRecording() {
        seconds = 0; promptIndex = 0; screen = .recording
        // Phase 3: begin real AVFoundation video+audio capture here.
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
        // Phase 5: upload video + STT transcript -> POST /api/products/from-video.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            guard let self else { return }
            self.valuation = .mock
            self.screen = .result
        }
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
