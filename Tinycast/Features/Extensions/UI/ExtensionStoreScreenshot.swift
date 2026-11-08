import AppKit
import ImageIO

/// A store screenshot decoded at the size it is shown, never at the width the store serves.
enum ExtensionStoreScreenshot {
    /// Long side; the strip draws them well under half of this on a 2x display.
    private static let maxPixel = 800

    /// A freshly-decoded, thereafter-immutable `NSImage` is safe to move across the actor boundary.
    private struct Decoded: @unchecked Sendable { let image: NSImage? }

    /// Nil on any failure or on cancel; nothing is cached here, so the view's state is the only copy.
    static func load(_ url: URL) async -> NSImage? {
        guard let data = try? await ExtensionStoreClient().download(url), !Task.isCancelled else {
            return nil
        }
        return await Task.detached(priority: .userInitiated) { Decoded(image: downsample(data)) }
            .value.image
    }

    private static func downsample(_ data: Data) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}
