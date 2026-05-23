import SwiftUI
import AVFoundation
import SwiftData

@MainActor
final class DiscoveryCaptureViewModel: ObservableObject {
    @Published var isCameraReady = false
    @Published var isCapturing = false
    @Published var isProcessing = false
    @Published var statusMessage = "Show Rare anything..."
    @Published var showPermissionAlert = false
    @Published var capturedItem: CapturedItem?
    @Published var errorMessage: String?
    
    let captureSession = AVCaptureSession()
    private var photoOutput = AVCapturePhotoOutput()
    private var currentDevice: AVCaptureDevice?
    private var photoCaptureDelegate: PhotoCaptureDelegate?
    
    // Injected via environment in the View
    var modelContext: ModelContext?
    
    // TODO: Inject real repository from RareImageryAPI package
    // var visionService: VisionService?
    
    func checkPermissionsAndSetup() {
        Task { await requestCameraAccessIfNeeded() }
    }
    
    private func requestCameraAccessIfNeeded() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized: await setupSession()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted { await setupSession() } else { showPermissionAlert = true }
        default: showPermissionAlert = true
        }
    }
    
    private func setupSession() async {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .photo
        
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            statusMessage = "Camera unavailable"
            return
        }
        currentDevice = device
        
        if captureSession.canAddInput(input) { captureSession.addInput(input) }
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
            photoOutput.isHighResolutionCaptureEnabled = true
        }
        
        captureSession.commitConfiguration()
        captureSession.startRunning()
        isCameraReady = true
        statusMessage = "Ready — tap to show Rare something"
    }
    
    func capturePhoto() async {
        guard isCameraReady && !isCapturing else { return }
        isCapturing = true
        statusMessage = "Capturing..."
        errorMessage = nil
        
        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        settings.flashMode = .auto
        settings.isHighResolutionPhotoEnabled = true
        
        let delegate = PhotoCaptureDelegate { [weak self] imageData in
            Task { @MainActor in await self?.processCapturedPhoto(imageData) }
        }
        photoCaptureDelegate = delegate
        photoOutput.capturePhoto(with: settings, delegate: delegate)
    }
    
    private func processCapturedPhoto(_ imageData: Data) async {
        isCapturing = false
        isProcessing = true
        statusMessage = "Rare is thinking..."
        
        guard let uiImage = UIImage(data: imageData),
              let processed = preprocessForGrokVision(uiImage),
              let processedData = processed.jpegData(compressionQuality: 0.85) else {
            isProcessing = false
            errorMessage = "Failed to process photo"
            return
        }
        
        let thumbnailData = createThumbnail(from: processed)
        
        // Create local SwiftData item immediately
        let item = CapturedItem(imageData: processedData, thumbnailData: thumbnailData)
        modelContext?.insert(item)
        
        // === REAL BACKEND CALL (uncomment when repository is ready) ===
        // do {
        //     let result = try await visionService?.analyze(imageData: processedData)
        //     item.suggestedTitle = result?.title
        //     item.suggestedDescription = result?.description
        //     item.suggestedTags = result?.tags ?? []
        //     item.analysisJSON = result?.rawJSON
        // } catch {
        //     errorMessage = error.localizedDescription
        // }
        
        // Temporary simulation until full repository integration
        try? await Task.sleep(for: .milliseconds(900))
        item.suggestedTitle = "Vintage Denim Jacket"
        item.suggestedDescription = "Washed denim with great texture. Perfect for a streetwear drop."
        item.suggestedTags = ["denim", "vintage", "jacket"]
        item.isProcessed = true
        
        capturedItem = item
        isProcessing = false
        statusMessage = "What Rare saw"
    }
    
    private func preprocessForGrokVision(_ image: UIImage) -> UIImage? {
        let maxSide: CGFloat = 1600
        let scale = min(maxSide / image.size.width, maxSide / image.size.height, 1)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        UIGraphicsBeginImageContextWithOptions(newSize, true, 1)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resized = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        return resized
    }
    
    private func createThumbnail(from image: UIImage) -> Data? {
        let size = CGSize(width: 280, height: 280)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        image.draw(in: CGRect(origin: .zero, size: size))
        let thumb = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return thumb?.jpegData(compressionQuality: 0.75)
    }
}

final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let onComplete: (Data) -> Void
    init(onComplete: @escaping (Data) -> Void) { self.onComplete = onComplete }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation() else { return }
        onComplete(data)
    }
}
