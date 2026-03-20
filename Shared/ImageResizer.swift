import UIKit
import ImageIO

enum ImageResizer {
    /// Downsample compressed image data (HEIC/JPEG/PNG) via ImageIO.
    /// Never decompresses the full image — safe for share extension memory limits.
    static func downsample(data: Data, maxDimension: CGFloat = 1024) -> Data? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
            return nil
        }
        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.7)
    }
}

enum ImageResizeError: LocalizedError {
    case compressionFailed
    case tooLarge(bytes: Int)

    var errorDescription: String? {
        switch self {
        case .compressionFailed:
            return "Could not compress the image."
        case .tooLarge(let bytes):
            let mb = Double(bytes) / 1_000_000
            return String(format: "Image too large (%.1f MB). Maximum is 1.5 MB.", mb)
        }
    }
}

extension UIImage {
    static let maxImageBytes = 1_500_000
    private static let qualitySteps: [CGFloat] = [0.7, 0.5, 0.3]

    func resizedForAPI(maxDimension: CGFloat = 1024) -> Data? {
        let scale = min(maxDimension / size.width, maxDimension / size.height, 1.0)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }

        for quality in Self.qualitySteps {
            if let data = resized.jpegData(compressionQuality: quality),
               data.count <= Self.maxImageBytes {
                return data
            }
        }
        // Last resort: return lowest quality regardless of size
        return resized.jpegData(compressionQuality: Self.qualitySteps.last ?? 0.3)
    }

    func resizedForAPIValidated(maxDimension: CGFloat = 1024) throws -> Data {
        guard let data = resizedForAPI(maxDimension: maxDimension) else {
            throw ImageResizeError.compressionFailed
        }
        if data.count > Self.maxImageBytes {
            throw ImageResizeError.tooLarge(bytes: data.count)
        }
        return data
    }
}
