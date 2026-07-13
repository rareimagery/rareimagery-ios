import Foundation
import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Extracts a JPEG poster frame from a local video for Drupal
/// `field_media_poster` — keeps ffmpeg off the VPS.
public enum VideoPosterExtractor: Sendable {
    public enum Failure: Error, Sendable {
        case cannotLoadTrack
        case cannotCopyCGImage
        case cannotEncodeJPEG
    }

    /// Captures a frame near `seconds` (default 0.5s) as JPEG ~quality 0.8.
    public static func jpegPoster(
        from videoURL: URL,
        at seconds: Double = 0.5,
        quality: CGFloat = 0.8
    ) async throws -> Data {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 1280)

        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        let cgImage: CGImage = try await withCheckedThrowingContinuation { cont in
            generator.generateCGImageAsynchronously(for: time) { image, _, error in
                if let error {
                    cont.resume(throwing: error)
                } else if let image {
                    cont.resume(returning: image)
                } else {
                    cont.resume(throwing: Failure.cannotCopyCGImage)
                }
            }
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw Failure.cannotEncodeJPEG
        }
        let props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, cgImage, props as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw Failure.cannotEncodeJPEG
        }
        return data as Data
    }
}
