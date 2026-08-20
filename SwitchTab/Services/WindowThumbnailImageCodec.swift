import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum WindowThumbnailEncodingFormat: Equatable, Sendable {
    case png
    case jpeg(quality: Double)
}

enum WindowThumbnailImageCodec {
    static func encode(
        _ image: CGImage,
        as format: WindowThumbnailEncodingFormat
    ) -> Data? {
        let data = NSMutableData()
        let type: UTType
        let properties: CFDictionary?

        switch format {
        case .png:
            type = .png
            properties = nil
        case .jpeg(let quality):
            type = .jpeg
            properties = [
                kCGImageDestinationLossyCompressionQuality:
                    min(1, max(0, quality))
            ] as CFDictionary
        }

        guard let destination = CGImageDestinationCreateWithData(
            data,
            type.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return data as Data
    }

    static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
