import SwiftUI

struct XConnectView: View {
    @EnvironmentObject var appState: AppState
    @State private var isConnecting = false
    @State private var error: String?
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 32) {
                Spacer()
                
                Text("Connect your X account")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                
                Text("We use your X profile so you can start creating and selling instantly. No email or password needed.")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Spacer()
                
                Button {
                    connectWithX()
                } label: {
                    HStack {
                        if isConnecting {
                            ProgressView()
                                .tint(.black)
                        } else {
                            Text("Connect with X")
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.white)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .disabled(isConnecting)
                .padding(.horizontal, 40)
                
                if let error = error {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
                
                Spacer()
            }
        }
    }
    
    private func connectWithX() {
        isConnecting = true
        error = nil
        
        // TODO: Call your existing AuthService / PKCE flow from RareImageryAPI
        // On success: appState.didConnectX()
        // On failure: show error
        
        // Placeholder simulation for now
        Task {
            try? await Task.sleep(for: .seconds(1))
            isConnecting = false
            appState.didConnectX()
        }
    }
}
