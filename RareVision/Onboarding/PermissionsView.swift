import SwiftUI

struct PermissionsView: View {
    @EnvironmentObject var appState: AppState
    @State private var cameraGranted = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 40) {
                Spacer()
                
                
                Image(systemName: "camera.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.white)
                
                Text("Enable your camera")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                
                
                Text("RareVision uses your camera to instantly analyze one item at a time with Grok Vision. Your photos stay private until you decide to create something.")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                
                Spacer()
                
                
                Button {
                    requestCameraPermission()
                } label: {
                    Text("Enable Camera")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.white)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 40)
                
                
                Button {
                    appState.startDiscoveryOnly() // fallback to photo library later
                } label: {
                    Text("Use Photo Library instead")
                        .foregroundStyle(.white.opacity(0.7))
                }
                
                Spacer()
            }
        }
    }
    
    private func requestCameraPermission() {
        // TODO: Use AVCaptureDevice.requestAccess and update appState
        // For now simulate grant
        cameraGranted = true
        appState.cameraPermissionGranted()
    }
}
