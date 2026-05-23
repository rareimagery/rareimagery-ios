import UIKit

enum ImageCompression {
    /// New BFF contract (2026-05-22): preprocess locally to ≤1280 px long edge,
    /// JPEG at 0.85 quality. Server skips its sharp resize when we send these
    /// already-normalized images.
    static let defaultMaxDimension: CGFloat = 1280
    static let defaultQuality: CGFloat = 0.85

    /// Resize to at most `maxDimension` on the long edge, then JPEG-encode at `quality`.
    static func compressForUpload(
        _ image: UIImage,
        maxDimension: CGFloat = defaultMaxDimension,
        quality: CGFloat = defaultQuality
    ) -> Data? {
        let resized = image.resized(toMaxDimension: maxDimension)
        return resized.jpegData(compressionQuality: quality)
    }

    static func compressForUpload(
        data: Data,
        maxDimension: CGFloat = defaultMaxDimension,
        quality: CGFloat = defaultQuality
    ) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return compressForUpload(image, maxDimension: maxDimension, quality: quality)
    }

    /// Produces a `data:image/jpeg;base64,...` URL string suitable for `imageUrls`
    /// in `POST /api/vision/analyze`.
    static func toBase64DataURL(_ jpegData: Data) -> String {
        "data:image/jpeg;base64,\(jpegData.base64EncodedString())"
    }
}

private extension UIImage {
    func resized(toMaxDimension maxDimension: CGFloat) -> UIImage {
        let longEdge = max(size.width, size.height)
        guard longEdge > maxDimension else { return self }
        let scale = maxDimension / longEdge
        let newSize = CGSize(width: floor(size.width * scale), height: floor(size.height * scale))
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
