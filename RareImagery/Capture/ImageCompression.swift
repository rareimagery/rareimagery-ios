import UIKit

enum ImageCompression {
    /// Resize to at most `maxDimension` on the long edge, then JPEG-encode at `quality`.
    /// Returns nil if compression fails.
    static func compressForUpload(
        _ image: UIImage,
        maxDimension: CGFloat = 1600,
        quality: CGFloat = 0.7
    ) -> Data? {
        let resized = image.resized(toMaxDimension: maxDimension)
        return resized.jpegData(compressionQuality: quality)
    }

    static func compressForUpload(
        data: Data,
        maxDimension: CGFloat = 1600,
        quality: CGFloat = 0.7
    ) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return compressForUpload(image, maxDimension: maxDimension, quality: quality)
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
