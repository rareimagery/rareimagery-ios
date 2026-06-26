import SwiftUI

/// Screen 1 — Instructions (variant C, bold-purple vault). Bud Hound + "Sell in
/// 3 steps" + gold "Start your video" CTA.
struct FunnelInstructionsView: View {
    let vm: FunnelViewModel
    @State private var floaty = false

    private let steps: [(icon: String, title: String, gold: Bool)] = [
        ("camera.fill", "Show it off in the camera", false),
        ("mic.fill", "Describe it out loud", false),
        ("sparkles", "Get its value from Grok", true),
    ]

    var body: some View {
        ZStack {
            AppColor.vaultGradient.ignoresSafeArea()
            VStack(spacing: 0) {
                RareWordmark().padding(.top, 8)

                Image("BudHound")
                    .resizable().scaledToFit()
                    .frame(width: 150, height: 150)
                    .shadow(color: .black.opacity(0.45), radius: 14, y: 14)
                    .rotationEffect(.degrees(-3))
                    .offset(y: floaty ? -9 : 0)
                    .padding(.top, 14)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                            floaty = true
                        }
                    }

                Text("● REC · YOUR PRODUCT")
                    .font(AppFont.mono(10.5, .semibold)).tracking(2)
                    .foregroundStyle(AppColor.gold)
                    .padding(.top, 8)

                (Text("Show us what's ") + Text("rare.").foregroundColor(AppColor.gold))
                    .font(AppFont.display(30, .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)

                VStack(spacing: 8) {
                    ForEach(steps.indices, id: \.self) { i in
                        stepCard(icon: steps[i].icon, title: steps[i].title, gold: steps[i].gold)
                    }
                }
                .padding(.top, 20)

                Spacer(minLength: 16)

                FunnelGoldButton(title: "Start your video") { vm.openCamera() }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
    }

    private func stepCard(icon: String, title: String, gold: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(gold ? AppColor.gold : Color(white: 0.9))
                .frame(width: 34, height: 34)
                .background(gold ? AppColor.goldSoft : Color.white.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 10))
            Text(title)
                .font(AppFont.display(14.5, .semibold))
                .foregroundStyle(.white)
            Spacer(minLength: 0)
        }
        .padding(11)
        .background(gold ? AppColor.goldSoft : Color.white.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(gold ? AppColor.borderGold : Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}
