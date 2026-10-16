import UIKit

enum MediaError: LocalizedError {
    case imageTooLarge, invalidImage, fileTooLarge
    var errorDescription: String? {
        switch self {
        case .imageTooLarge: return "Images must be smaller than 8 MB."
        case .invalidImage: return "Could not read image."
        case .fileTooLarge: return "Files must be smaller than 5 MB."
        }
    }
}

enum MediaProcessor {
    static let maxImageBytes = 8 * 1024 * 1024
    static func prepareImage(_ data: Data) throws -> Data {
        guard data.count <= maxImageBytes else { throw MediaError.imageTooLarge }
        guard let img = UIImage(data: data) else { throw MediaError.invalidImage }
        // Downscale to max 1600px long edge
        let maxLen: CGFloat = 1600
        let scale = min(1, maxLen / max(img.size.width, img.size.height))
        if scale < 1 {
            let newSize = CGSize(width: img.size.width*scale, height: img.size.height*scale)
            let renderer = UIGraphicsImageRenderer(size: newSize)
            let resized = renderer.image { _ in img.draw(in: CGRect(origin: .zero, size: newSize)) }
            if let jpeg = resized.jpegData(compressionQuality: 0.8) { return jpeg }
        }
        return data
    }
}
