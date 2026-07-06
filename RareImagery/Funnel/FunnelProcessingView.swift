import SwiftUI

/// Screen 3 — Processing. "GROK IS READING" + Bud spinner + progress checklist.
struct FunnelProcessingView: View {
    let vm: FunnelViewModel
    @State private var spin = false

    var body: some View {
        ZStack {
            AppColor.vaultGradient.ignoresSafeArea()
            VStack(spacing: 22) {
                ZStack {
                    Circle().stroke(AppColor.gold.opacity(0.16), lineWidth: 4)
                        .frame(width: 96, height: 96)
                    Circle().trim(from: 0, to: 0.25)
                        .stroke(AppColor.gold, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 96, height: 96)
                        .rotationEffect(.degrees(spin ? 360 : 0))
                        .animation(.linear(duration: 0.85).repeatForever(autoreverses: false), value: spin)
                    Image("BudHound").resizable().scaledToFit().frame(width: 64, height: 64)
                }
                VStack(spacing: 8) {
                    Text("GROK IS READING")
                        .font(AppFont.mono(11)).tracking(2).foregroundStyle(AppColor.gold)
                    Text("Sniffing out the value…")
                        .font(AppFont.display(22, .semibold)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 10) {
                    checkRow("Watched your video", done: true)
                    checkRow("Heard your description", done: true)
                    checkRow("Pricing against the market…", done: false)
                }
                .frame(maxWidth: 220)
            }
            .padding(30)
        }
        .onAppear { spin = true }
    }

    private func checkRow(_ text: String, done: Bool) -> some View {
        HStack(spacing: 10) {
            ZStack {
                if done {
                    Circle().fill(AppColor.success).frame(width: 20, height: 20)
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                } else {
                    Circle().stroke(.white.opacity(0.25), lineWidth: 2).frame(width: 20, height: 20)
                }
            }
            Text(text)
                .font(AppFont.bodyText(13))
                .foregroundStyle(done ? Color(white: 0.85) : .white.opacity(0.45))
            Spacer(minLength: 0)
        }
    }
}
