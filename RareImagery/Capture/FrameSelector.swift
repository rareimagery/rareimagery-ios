import AVFoundation
import CoreImage
import UIKit

/// Reduces a recorded clip to up to `maxCount` **sharp, time-diverse** frames,
/// returned as base64 JPEG data URLs ready for `/api/vision/analyze`.
/// Strategy: split the clip into `maxCount` time windows; in each, sample a few
/// candidates and keep the sharpest (Laplacian-edge energy). Reuses
/// `ImageCompression` so frames match the photo pipeline (≤1280px, JPEG 0.85).
enum FrameSelector {
    static func selectFrames(from url: URL, maxCount: Int = 4) async -> [String] {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration), duration.seconds > 0 else { return [] }
        let total = duration.seconds

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = CGSize(width: 1600, height: 1600)

        let context = CIContext(options: [.workingColorSpace: NSNull()])
        let windows = max(1, maxCount)
        let perWindow = 3
        var dataURLs: [String] = []

        for w in 0..<windows {
            let windowStart = total * Double(w) / Double(windows)
            let windowLen = total / Double(windows)
            var best: (score: Float, image: UIImage)?
            for c in 0..<perWindow {
                let t = windowStart + windowLen * (Double(c) + 0.5) / Double(perWindow)
                guard let cg = try? await generator.image(at: CMTime(seconds: t, preferredTimescale: 600)).image
                else { continue }
                let score = sharpness(cg, context)
                if best == nil || score > best!.score { best = (score, UIImage(cgImage: cg)) }
            }
            if let best, let jpeg = ImageCompression.compressForUpload(best.image) {
                dataURLs.append(ImageCompression.toBase64DataURL(jpeg))
            }
        }
        return dataURLs
    }

    /// Relative sharpness = average Laplacian-edge magnitude (more edges ⇒ sharper).
    /// Good enough to rank frames of the same clip.
    private static func sharpness(_ cg: CGImage, _ context: CIContext) -> Float {
        let image = CIImage(cgImage: cg)
        let weights = CIVector(values: [0, -1, 0, -1, 4, -1, 0, -1, 0], count: 9)
        guard
            let edges = CIFilter(name: "CIConvolution3X3", parameters: [
                kCIInputImageKey: image, "inputWeights": weights, "inputBias": 0.0,
            ])?.outputImage,
            let average = CIFilter(name: "CIAreaAverage", parameters: [
                kCIInputImageKey: edges, kCIInputExtentKey: CIVector(cgRect: image.extent),
            ])?.outputImage
        else { return 0 }
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(average, toBitmap: &pixel, rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: nil)
        return Float(pixel[0]) + Float(pixel[1]) + Float(pixel[2])
    }
}
