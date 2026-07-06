import SwiftUI

/// Screen 2 — Record / Recording. Bud Hound IS the record button. Phase 2 uses
/// the mock recorder (vm timer + prompts); Phase 3 swaps real AVFoundation.
struct FunnelRecordView: View {
    let vm: FunnelViewModel
    @State private var pulse = false

    private var isRecording: Bool { vm.screen == .recording }
    private var rec: Color { Color(red: 214/255, green: 69/255, blue: 93/255) }

    var body: some View {
        ZStack {
            AppColor.vaultGradient.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                if !isRecording {
                    VStack(spacing: 4) {
                        Text("Frame your product")
                            .font(AppFont.display(21, .semibold)).foregroundStyle(.white)
                        Text("Tap Bud and start talking.")
                            .font(AppFont.bodyText(13)).foregroundStyle(Color(white: 0.85))
                    }
                    .padding(.top, 12)
                }

                viewfinder
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, 18)
                    .padding(.horizontal, 6)

                VStack(spacing: 13) {
                    budButton
                    Text(isRecording ? "TAP BUD TO FINISH" : "TAP BUD TO RECORD")
                        .font(AppFont.mono(11)).tracking(2)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
        }
    }

    private var topBar: some View {
        HStack {
            if isRecording {
                HStack(spacing: 7) {
                    Circle().fill(rec).frame(width: 8, height: 8)
                    Text("REC \(vm.timeLabel)").font(AppFont.mono(12, .semibold))
                }
                .foregroundStyle(Color(red: 1, green: 0.56, blue: 0.63))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(rec.opacity(0.18), in: Capsule())
                .overlay(Capsule().stroke(rec.opacity(0.5), lineWidth: 1))
            } else {
                Text("STEP 02 · CAMERA")
                    .font(AppFont.mono(10.5, .semibold)).tracking(2)
                    .foregroundStyle(AppColor.gold)
            }
            Spacer()
            RareWordmark(size: 15)
        }
    }

    private var viewfinder: some View {
        ZStack {
            CameraPreview(session: vm.capture.session)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            CornerBrackets(color: (isRecording ? rec : AppColor.gold).opacity(0.8))
            if isRecording {
                VStack {
                    VStack(spacing: 6) {
                        Text("BUD ASKS")
                            .font(AppFont.mono(10)).tracking(2)
                            .foregroundStyle(.white.opacity(0.5))
                        Text(vm.currentPrompt)
                            .font(AppFont.display(22, .semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .transition(.opacity)
                            .id(vm.currentPrompt)
                    }
                    .padding(.top, 28)
                    Spacer()
                    Waveform().padding(.bottom, 16)
                }
                .animation(.easeInOut, value: vm.currentPrompt)
            }
        }
    }

    private var budButton: some View {
        Button {
            isRecording ? vm.stopRecording() : vm.startRecording()
        } label: {
            ZStack {
                if isRecording {
                    Circle().stroke(AppColor.gold, lineWidth: 3)
                        .frame(width: 132, height: 132)
                        .scaleEffect(pulse ? 1.4 : 1).opacity(pulse ? 0 : 0.6)
                }
                Circle()
                    .fill(RadialGradient(colors: [.white, Color(red: 0.96, green: 0.93, blue: 0.97)],
                                         center: .init(x: 0.5, y: 0.36), startRadius: 2, endRadius: 80))
                    .frame(width: 132, height: 132)
                    .overlay(Circle().stroke(AppColor.gold, lineWidth: 4))
                    .shadow(color: AppColor.gold.opacity(0.5), radius: 16, y: 10)
                Image("BudHound").resizable().scaledToFit()
                    .frame(width: 118, height: 118).offset(y: 3)
            }
        }
        .onAppear {
            guard isRecording else { return }
            withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) { pulse = true }
        }
        .onChange(of: isRecording) { _, rec in
            pulse = false
            if rec { withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) { pulse = true } }
        }
    }
}

/// Gold/red corner brackets around the viewfinder.
private struct CornerBrackets: View {
    let color: Color
    var body: some View {
        GeometryReader { _ in
            ForEach(0..<4, id: \.self) { i in
                bracket(index: i)
            }
        }
    }
    @ViewBuilder private func bracket(index i: Int) -> some View {
        let top = i < 2
        let leading = i % 2 == 0
        Path { p in
            p.move(to: CGPoint(x: leading ? 0 : 30, y: top ? 30 : 0))
            p.addLine(to: CGPoint(x: leading ? 0 : 30, y: top ? 0 : 30))
            p.addLine(to: CGPoint(x: leading ? 30 : 0, y: top ? 0 : 30))
        }
        .stroke(color, lineWidth: 2)
        .frame(width: 30, height: 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity,
               alignment: Alignment(horizontal: leading ? .leading : .trailing,
                                    vertical: top ? .top : .bottom))
    }
}

/// Animated gold waveform bars.
private struct Waveform: View {
    @State private var on = false
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<13, id: \.self) { i in
                Capsule().fill(AppColor.gold)
                    .frame(width: 4, height: 46)
                    .scaleEffect(y: on ? 1 : 0.3, anchor: .bottom)
                    .animation(.easeInOut(duration: 0.9).repeatForever().delay(Double(i) * 0.07), value: on)
            }
        }
        .frame(height: 46)
        .onAppear { on = true }
    }
}
