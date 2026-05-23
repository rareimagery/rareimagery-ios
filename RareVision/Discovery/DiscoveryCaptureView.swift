import SwiftUI
import AVFoundation

struct DiscoveryCaptureView: View {
    @StateObject private var viewModel = DiscoveryCaptureViewModel()
    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if viewModel.isCameraReady {
                CameraPreview(session: viewModel.captureSession)
                    .ignoresSafeArea()
            } else {
                ProgressView()
                    .tint(.white)
            }
            
            VStack {
                // Top bar
                HStack {
                    Text("DISCOVERY MODE")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                    
                    Spacer()
                    
                    Button {
                        appState.navigateBack()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding(.top, 60)
                .padding(.horizontal)
                
                Spacer()
                
                // Status + Capture Button
                VStack(spacing: 24) {
                    if viewModel.isProcessing {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.4)
                        Text(viewModel.statusMessage)
                            .font(.callout)
                            .foregroundStyle(.white)
                    } else if viewModel.isCapturing {
                        Text("Capturing...")
                            .font(.headline)
                            .foregroundStyle(.white)
                    } else {
                        Button {
                            Task { await viewModel.capturePhoto() }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(.white)
                                    .frame(width: 82, height: 82)
                                Circle()
                                    .stroke(.white, lineWidth: 5)
                                    .frame(width: 98, height: 98)
                            }
                        }
                        .disabled(!viewModel.isCameraReady)
                        .shadow(radius: 20)
                    }
                    
                    Text(viewModel.statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                }
                .padding(.bottom, 80)
            }
        }
        .onAppear {
            viewModel.modelContext = modelContext
            viewModel.checkPermissionsAndSetup()
        }
        .alert("Camera Access Needed", isPresented: $viewModel.showPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("RareVision needs your camera to analyze one item at a time with Grok Vision.")
        }
        .sheet(item: $viewModel.capturedItem) { item in
            DiscoveryResultView(capturedItem: item)
        }
    }
}

// Reusable camera preview (can be shared with other capture screens)
struct CameraPreview: UIViewControllerRepresentable {
    let session: AVCaptureSession
    
    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = vc.view.bounds
        vc.view.layer.addSublayer(previewLayer)
        return vc
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        if let previewLayer = uiViewController.view.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            previewLayer.frame = uiViewController.view.bounds
        }
    }
}
