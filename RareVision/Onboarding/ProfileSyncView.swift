import SwiftUI

struct ProfileSyncView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 32) {
                Spacer()
                
                Text("You're in.")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                
                VStack(spacing: 16) {
                    // TODO: Show real X avatar + handle from AuthService
                    Circle()
                        .fill(.white.opacity(0.2))
                        .frame(width: 100, height: 100)
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.largeTitle)
                                .foregroundStyle(.white)
                        }
                    
                    Text("@yourhandle")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                    
                    Text("X profile synced. Your RareVision store is ready.")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
                
                Spacer()
                
                
                Button {
                    appState.startDiscovery()
                } label: {
                    Text("Start capturing")
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
