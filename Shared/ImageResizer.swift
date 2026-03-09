import UIKit

enum ImageResizeError: LocalizedError {
    case compressionFailed
    case tooLarge(bytes: Int)

    var errorDescription: String? {
        switch self {
        case .compressionFailed:
            return "Could not compress the image."
        case .tooLarge(let bytes):
            let mb = Double(bytes) / 1_000_000
            return String(format: "Image too large (%.1f MB). Maximum is 5 MB.", mb)
        }
    }
}

extension UIImage {
    static let maxImageBytes = 5_000_000

    func resizedForAPI(maxDimension: CGFloat = 1024) -> Data? {
        let scale = min(maxDimension / size.width, maxDimension / size.height, 1.0)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: 0.7)
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
