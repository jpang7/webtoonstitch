import Foundation
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics

enum ImageImportError: LocalizedError {
    case decodeFailed
    case encodeFailed
    case readMetadataFailed

    var errorDescription: String? {
        switch self {
        case .decodeFailed: return "Couldn't decode the picked image."
        case .encodeFailed: return "Couldn't save the resized panel."
        case .readMetadataFailed: return "Couldn't read image metadata."
        }
    }
}

struct ResizedPanel: Sendable {
    let width: Int
    let height: Int
}

enum ImageImporter {
    /// Resizes the given image data to exactly `targetWidth` pixels wide
    /// (preserving aspect ratio after honoring EXIF orientation) and writes
    /// a PNG to `destinationURL`. The full source is never decoded into RAM.
    nonisolated static func importPanel(
        data: Data,
        targetWidth: Int,
        destinationURL: URL
    ) throws -> ResizedPanel {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ImageImportError.decodeFailed
        }
        guard let rawProps = CGImageSourceCopyPropertiesAtIndex(src, 0, nil),
              let props = rawProps as? [CFString: Any]
        else {
            throw ImageImportError.readMetadataFailed
        }

        let rawW = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        let rawH = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
        let needsSwap = (5...8).contains(orientation)
        let srcW = needsSwap ? rawH : rawW
        let srcH = needsSwap ? rawW : rawH

        guard srcW > 0, srcH > 0 else {
            throw ImageImportError.readMetadataFailed
        }

        let scaleRatio = Double(max(srcW, srcH)) / Double(srcW)
        let maxPixel = max(targetWidth, Int(ceil(Double(targetWidth) * scaleRatio)))

        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else {
            throw ImageImportError.decodeFailed
        }

        let exactW = targetWidth
        let exactH = max(
            1,
            Int((Double(thumb.height) * Double(exactW) / Double(thumb.width)).rounded())
        )

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: exactW,
            height: exactH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ImageImportError.encodeFailed
        }
        ctx.interpolationQuality = .high
        ctx.draw(thumb, in: CGRect(x: 0, y: 0, width: exactW, height: exactH))

        guard let finalCG = ctx.makeImage() else {
            throw ImageImportError.encodeFailed
        }

        guard let dest = CGImageDestinationCreateWithURL(
            destinationURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw ImageImportError.encodeFailed
        }
        CGImageDestinationAddImage(dest, finalCG, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw ImageImportError.encodeFailed
        }

        return ResizedPanel(width: exactW, height: exactH)
    }
}
