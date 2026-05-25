import Foundation
import UIKit

/// Load a local image file, downscale to fit `maxDimension` px on its
/// longest edge, JPEG-encode at `quality`, and return as a
/// `data:image/jpeg;base64,…` URL string ready to send to
/// `/api/v1/vision/merch-ideas` or `/api/design-studio/generate`.
///
/// Why downscale before send:
///   - Full-res iPhone JPEGs are 3–6 MB. Grok charges per image token; the
///     `design-studio/generate` route caps `reference_image` data URLs at
///     6 MB; cost + latency penalize huge images for no quality benefit
///     in a 512–1024px composite target.
///   - 1024px on the long edge after JPEG q=0.85 lands well under 1 MB
///     for typical iPhone front-camera shots.
///
/// Runs on a detached task — CPU-bound image work shouldn't block the
/// MainActor that's driving the OnePageCreator UI.
enum ImageDataURL {
    static func make(
        from fileURL: URL,
        maxDimension: CGFloat = 1024,
        quality: CGFloat = 0.85
    ) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            guard let image = UIImage(contentsOfFile: fileURL.path) else {
                throw ImageDataURLError.couldNotLoad(fileURL.lastPathComponent)
            }
            let downscaled = image.downscaled(toLongestEdge: maxDimension)
            guard let jpeg = downscaled.jpegData(compressionQuality: quality) else {
                throw ImageDataURLError.couldNotEncode
            }
            return "data:image/jpeg;base64," + jpeg.base64EncodedString()
        }.value
    }
}

enum ImageDataURLError: LocalizedError, Sendable {
    case couldNotLoad(String)
    case couldNotEncode

    var errorDescription: String? {
        switch self {
        case .couldNotLoad(let name): return "Couldn't load image \(name)."
        case .couldNotEncode:         return "Couldn't encode image for upload."
        }
    }
}

private extension UIImage {
    /// Returns a copy scaled so the longest edge is `maxLongestEdge` px,
    /// preserving aspect ratio. No-op if already smaller.
    /// Renders at scale=1 because the caller wants raw pixels for upload,
    /// not display.
    func downscaled(toLongestEdge maxLongestEdge: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxLongestEdge else { return self }

        let scale = maxLongestEdge / longest
        let newSize = CGSize(
            width: floor(size.width * scale),
            height: floor(size.height * scale)
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true

        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
