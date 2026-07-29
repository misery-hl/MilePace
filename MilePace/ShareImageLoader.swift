import UIKit
import ImageIO

/// Decodes a PhotosPicker image at a size suitable for a 4:5 share card.
@MainActor
enum ShareImageLoader {
    static let exportPixelSize = CGSize(width: 1_080, height: 1_350)

    /// Returns a decoded, orientation-corrected image, or nil for invalid data.
    static func image(from data: Data) -> UIImage? {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) != nil,
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.intValue > 0,
              height.intValue > 0 else {
            return nil
        }

        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let hasTransposedOrientation = (5...8).contains(orientation)
        let displayWidth = hasTransposedOrientation ? height.intValue : width.intValue
        let displayHeight = hasTransposedOrientation ? width.intValue : height.intValue
        let scale = max(
            exportPixelSize.width / CGFloat(displayWidth),
            exportPixelSize.height / CGFloat(displayHeight)
        )
        let maximumPixelSize = (
            CGFloat(max(displayWidth, displayHeight)) * min(scale, 1)
        ).rounded(.up)

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
        ]

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        return UIImage(cgImage: thumbnail, scale: 1, orientation: .up)
    }
}
