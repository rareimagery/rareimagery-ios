import SwiftUI

/// Screen 4 — Result (the hook). Grok's read + gold value card + insights, and
/// the **account wall**: "Create your store to sell" gates X-OAuth.
struct FunnelResultView: View {
    let vm: FunnelViewModel
    var onExit: (() -> Void)? = nil
    @Environment(AppState.self) private var state
    @State private var coordinator = AuthCoordinator()
    @State private var authing = false

    private var v: FunnelValuation { vm.valuation ?? .mock }
    private var goldText: Color { Color(red: 0.886, green: 0.757, blue: 0.349) }

    var body: some View {
        ZStack {
            AppColor.vaultGradient.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack { Spacer(); RareWordmark(size: 15) }

                    HStack(spacing: 8) {
                        Image("BudHound").resizable().scaledToFit().frame(width: 28, height: 28)
                            .padding(2).background(Color(red: 0.96, green: 0.93, blue: 0.97), in: Circle())
                        Text("GROK'S READ · CONFIDENCE \(v.confidence)%")
                            .font(AppFont.mono(10.5, .semibold)).tracking(1.5)
                            .foregroundStyle(AppColor.gold)
                    }
                    .padding(.top, 16)

                    Text(v.title)
                        .font(AppFont.display(25, .semibold)).foregroundStyle(.white)
                        .padding(.top, 14)

                    valueCard.padding(.top, 18)
                    pills.padding(.top, 14)

                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(v.insights, id: \.self) { ins in
                            HStack(alignment: .top, spacing: 9) {
                                Text("●").foregroundStyle(AppColor.gold).font(.system(size: 10)).padding(.top, 2)
                                Text(ins).font(AppFont.bodyText(13)).foregroundStyle(Color(white: 0.85))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.top, 16)

                    VStack(spacing: 10) {
                        FunnelGoldButton(title: authing ? "Connecting to X…" : (state.session.isAnonymous ? "Claim this draft" : "Create your store to sell")) {
                            createStore()
                        }
                        .disabled(authing)
                        Text("NEXT · ACCOUNT CREATION")
                            .font(AppFont.mono(10)).tracking(1.5).foregroundStyle(.white.opacity(0.4))
                        Button { vm.reset() } label: {
                            Text("Record again")
                                .font(AppFont.bodyText(14)).foregroundStyle(.white.opacity(0.7))
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                        }
                        if let onExit {
                            Button(action: onExit) {
                                Text("Explore the app")
                                    .font(AppFont.bodyText(14))
                                    .foregroundStyle(.white.opacity(0.7))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                            }
                        }
                    }
                    .padding(.top, 20)
                }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 28)
            }
        }
    }

    private var valueCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ESTIMATED VALUE")
                .font(AppFont.mono(10.5, .semibold)).tracking(1.5).foregroundStyle(goldText)
            Text("$\(v.valueLow) – $\(v.valueHigh)")
                .font(AppFont.mono(34, .bold)).foregroundStyle(.white)
            (Text("Suggested list price ") + Text("$\(v.suggested)").foregroundColor(AppColor.gold))
                .font(AppFont.bodyText(12.5)).foregroundStyle(Color(white: 0.85))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [AppColor.gold.opacity(0.20), AppColor.gold.opacity(0.05)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 18)
        )
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(AppColor.borderGold, lineWidth: 1))
    }

    private var pills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                pill(v.category, gold: false)
                pill("Condition: \(v.condition)", gold: false)
                pill("Rarity \(String(format: "%.1f", v.rarity)) / 10", gold: true)
            }
        }
    }

    private func pill(_ text: String, gold: Bool) -> some View {
        Text(text)
            .font(AppFont.mono(11))
            .foregroundStyle(gold ? goldText : Color(red: 0.894, green: 0.839, blue: 0.925))
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(gold ? AppColor.gold.opacity(0.16) : Color.white.opacity(0.08), in: Capsule())
            .overlay(Capsule().stroke(gold ? AppColor.borderGold : Color.white.opacity(0.14), lineWidth: 1))
    }

    private func createStore() {
        if state.session.isSignedIn {
            // Phase 5: adopt the storeless valuation into a new store + route on.
        } else {
            Task {
                authing = true
                let draftToken = state.session.isAnonymous ? (try? await state.keychain.get(.pendingDraftToken)) : nil
                await coordinator.signInWithX(state: state, draftToken: draftToken)
                authing = false
            }
        }
    }
}
