import SwiftUI

struct OnboardingCompleteView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 40) {
                Spacer()
                
                
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.green)
                
                
                Text("You're all set.")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                
                
                Text("Your first capture is ready. Keep exploring or turn it into merch whenever you're ready.")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                
                
                Spacer()
                
                
                Button {
                    appState.goToMainApp()
                } label: {
                    Text("Start using RareVision")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.white)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 40)
                
                Spacer()
            }
        }
    }
}
