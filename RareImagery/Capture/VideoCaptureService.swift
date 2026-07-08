import AVFoundation
import SwiftUI

/// Records a product clip (video + audio) to a temp `.mov` via AVFoundation.
/// The funnel's `FunnelViewModel` drives REC state/timer; this service owns the
/// `AVCaptureSession` (exposed for the preview) and returns the recorded file URL.
/// Phase 3 — verified by compile here; record/playback is a device test.
/// @unchecked Sendable: all mutable state (`configured`, `stopContinuation`)
/// is confined to `sessionQueue`; the delegate callback hops onto it too.
final class VideoCaptureService: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let sessionQueue = DispatchQueue(label: "com.rareimagery.capture.session")
    private var configured = false
    private var stopContinuation: CheckedContinuation<URL?, Never>?

    /// Camera + mic permission. Returns true only if both are granted.
    func requestPermissions() async -> Bool {
        let cam = await AVCaptureDevice.requestAccess(for: .video)
        let mic = await AVCaptureDevice.requestAccess(for: .audio)
        return cam && mic
    }

    /// Configure inputs/outputs once, then start the session (off the main thread).
    func configureIfNeeded() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            sessionQueue.async {
                if !self.configured {
                    self.configured = true
                    self.session.beginConfiguration()
                    self.session.sessionPreset = .high
                    if let cam = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                       let videoIn = try? AVCaptureDeviceInput(device: cam),
                       self.session.canAddInput(videoIn) {
                        self.session.addInput(videoIn)
                    }
                    if let mic = AVCaptureDevice.default(for: .audio),
                       let audioIn = try? AVCaptureDeviceInput(device: mic),
                       self.session.canAddInput(audioIn) {
                        self.session.addInput(audioIn)
                    }
                    if self.session.canAddOutput(self.movieOutput) {
                        self.session.addOutput(self.movieOutput)
                    }
                    self.session.commitConfiguration()
                }
                if !self.session.isRunning { self.session.startRunning() }
                cont.resume()
            }
        }
    }

    func startRecording() {
        sessionQueue.async {
            guard self.movieOutput.connection(with: .video) != nil, !self.movieOutput.isRecording else { return }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mov")
            self.movieOutput.startRecording(to: url, recordingDelegate: self)
        }
    }

    /// Stops recording; resolves with the file URL once writing finishes.
    func stopRecording() async -> URL? {
        await withCheckedContinuation { (cont: CheckedContinuation<URL?, Never>) in
            sessionQueue.async {
                guard self.movieOutput.isRecording else { cont.resume(returning: nil); return }
                self.stopContinuation = cont
                self.movieOutput.stopRecording()
            }
        }
    }

    // AVCaptureFileOutputRecordingDelegate — arrives on AVFoundation's internal
    // queue; hop to sessionQueue so stopContinuation stays queue-confined.
    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {
        sessionQueue.async {
            let cont = self.stopContinuation
            self.stopContinuation = nil
            cont?.resume(returning: error == nil ? outputFileURL : nil)
        }
    }
}

/// Live camera preview backed by `AVCaptureVideoPreviewLayer`.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
