import SwiftUI
import AVFoundation
import Photos
import SwiftData

@MainActor
final class DiscoveryCaptureViewModel: ObservableObject {
    // Published state
    @Published var isCameraReady = false
    @Published var isCapturing = false
    @Published var isProcessing = false
    @Published var statusMessage = "Point at one thing you love..."
    @Published var showPermissionAlert = false
    @Published var capturedItem: CapturedItem?
    @Published var errorMessage: String?
    
    let captureSession = AVCaptureSession()
    private var photoOutput = AVCapturePhotoOutput()
    private var currentDevice: AVCaptureDevice?
    private var photoCaptureDelegate: PhotoCaptureDelegate?
    
    // Injected or environment objects (wire in Xcode)
    var modelContext: ModelContext?
    var productRepository: ProductRepository?   // From RareImageryAPI package
    
    // MARK: - Camera Setup
    func checkPermissionsAndSetup() {
        Task {
            await requestCameraAccessIfNeeded()
        }
    }
    
    private func requestCameraAccessIfNeeded() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            await setupSession()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted {
                await setupSession()
            } else {
                showPermissionAlert = true
            }
        default:
            showPermissionAlert = true
        }
    }
    
    private func setupSession() async {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .photo
        
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            statusMessage = "Camera not available"
            return
        }
        currentDevice = device
        
        if captureSession.canAddInput(input) { captureSession.addInput(input) }
        
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
            photoOutput.isHighResolutionCaptureEnabled = true
            photoOutput.maxPhotoQualityPrioritization = .quality
        }
        
        captureSession.commitConfiguration()
        captureSession.startRunning()
        
        isCameraReady = true
        statusMessage = "Ready — tap to capture one thing"
    }
    
    // MARK: - Capture
    func capturePhoto() async {
        guard isCameraReady && !isCapturing else { return }
        
        isCapturing = true
        statusMessage = "Capturing..."
        errorMessage = nil
        
        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        settings.flashMode = .auto
        settings.isHighResolutionPhotoEnabled = true
        
        let delegate = PhotoCaptureDelegate { [weak self] imageData in
            Task { @MainActor in
                await self?.processCapturedPhoto(imageData)
            }
        }
        photoCaptureDelegate = delegate
        photoOutput.capturePhoto(with: settings, delegate: delegate)
    }
    
    private func processCapturedPhoto(_ imageData: Data) async {
        isCapturing = false
        isProcessing = true
        statusMessage = "Analyzing with Grok Vision..."
        
        // 1. Preprocess (resize + optional sharpen)
        guard let uiImage = UIImage(data: imageData),
              let processedImage = preprocessForGrokVision(uiImage),
              let processedData = processedImage.jpegData(compressionQuality: 0.85) else {
            isProcessing = false
            errorMessage = "Failed to process image"
            return
        }
        
        // 2. Create thumbnail
        let thumbnail = createThumbnail(from: processedImage)
        
        // 3. Save to SwiftData
        let item = CapturedItem(imageData: processedData, thumbnailData: thumbnail)
        modelContext?.insert(item)
        
        // 4. Call backend / Grok Vision (via ProductRepository or dedicated endpoint)
        // TODO: Wire real call in Xcode
        // Example:
        // if let repo = productRepository {
        //     do {
        //         let result = try await repo.createFromImages(images: [processedData], intent: .discovery)
        //         item.analysisJSON = result.rawJSON
        //         item.suggestedTitle = result.title
        //         ...
        //     } catch { ... }
        // }
        
        // For now: simulate quick analysis
        try? await Task.sleep(for: .milliseconds(800))
        
        item.suggestedTitle = "Vintage Denim Jacket"
        item.suggestedDescription = "Classic washed denim with great texture. Perfect for streetwear drops."
        item.suggestedTags = ["denim", "vintage", "jacket", "streetwear"]
        item.isProcessed = true
        
        capturedItem = item
        
        isProcessing = false
        statusMessage = "Analysis complete"
    }
    
    // MARK: - Preprocessing (from ios skill)
    private func preprocessForGrokVision(_ image: UIImage) -> UIImage? {
        let maxSide: CGFloat = 1600
        let scale = min(maxSide / image.size.width, maxSide / image.size.height, 1.0)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        
        UIGraphicsBeginImageContextWithOptions(newSize, true, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resized = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        
        return resized
    }
    
    private func createThumbnail(from image: UIImage) -> Data? {
        let size = CGSize(width: 300, height: 300)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        image.draw(in: CGRect(origin: .zero, size: size))
        let thumbnail = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return thumbnail?.jpegData(compressionQuality: 0.7)
    }
}

// Photo delegate bridge
final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let onComplete: (Data) -> Void
    
    init(onComplete: @escaping (Data) -> Void) {
        self.onComplete = onComplete
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print("[Discovery] Capture error: \(error)")
            return
        }
        guard let data = photo.fileDataRepresentation() else { return }
        onComplete(data)
    }
}
