import AppKit
import Foundation

struct PreparedImage {
    let data: Data
    let mimeType: String
}

enum MediaError: LocalizedError {
    case imageTooLarge, invalidImage, encodingFailed, fileTooLarge

    var errorDescription: String? {
        switch self {
        case .imageTooLarge: return "Images must be smaller than 25 MB."
        case .invalidImage: return "The selected file is not a supported image."
        case .encodingFailed: return "The image could not be prepared for upload."
        case .fileTooLarge: return "Files must be smaller than 5 MB."
        }
    }
}

enum MediaProcessor {
    static let maximumInputBytes = 25 * 1024 * 1024
    static let maximumImageDimension: CGFloat = 2_048

    static func prepareImage(_ data: Data) throws -> PreparedImage {
        guard data.count <= maximumInputBytes else { throw MediaError.imageTooLarge }
        guard let source = NSImage(data: data), source.size.width > 0, source.size.height > 0 else {
            throw MediaError.invalidImage
        }
        let scale = min(1, maximumImageDimension / max(source.size.width, source.size.height))
        let size = NSSize(
            width: max(1, floor(source.size.width * scale)),
            height: max(1, floor(source.size.height * scale))
        )
        let target = NSImage(size: size)
        target.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(in: NSRect(origin: .zero, size: size))
        target.unlockFocus()
        guard let tiff = target.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let encoded = bitmap.representation(
                using: .jpeg,
                properties: [.compressionFactor: 0.85]
              ) else {
            throw MediaError.encodingFailed
        }
        return PreparedImage(data: encoded, mimeType: "image/jpeg")
    }


}
