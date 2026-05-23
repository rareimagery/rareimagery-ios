import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var appState: AppState // Wire in Xcode
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 40) {
                Spacer()
                
                // Brand
                Text("RAREVISION")
                    .font(.system(size: 42, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                
                Text("Turn anything you see\ninto merch in 60 seconds.")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                
                Spacer()
                
                // Primary CTA
                Button {
                    appState.navigateToXConnect()
                } label: {
                    Text("Connect with X")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.white)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(.horizontal, 40)
                
                Button {
                    appState.startDiscoveryOnly()
                } label: {
                    Text("Just explore first")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
                
                Spacer()
            }
        }
    }
}
