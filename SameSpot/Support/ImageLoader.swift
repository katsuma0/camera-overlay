import ImageIO
import SwiftUI
import UIKit

/// Decodes photos at the size they're shown, off the main thread. Full 12 MP decodes for a
/// grid of thumbnails would eat memory fast.
final class ImageLoader {
    static let shared = ImageLoader()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 300
        // Full screen decodes are about 17 MB each. Cap the total, not just the count.
        cache.totalCostLimit = 200 * 1024 * 1024
    }

    func cachedImage(at url: URL, maxPixel: Int) -> UIImage? {
        cache.object(forKey: Self.key(url, maxPixel))
    }

    func image(at url: URL, maxPixel: Int) async -> UIImage? {
        let key = Self.key(url, maxPixel)
        if let hit = cache.object(forKey: key) {
            return hit
        }
        let work = Task.detached(priority: .userInitiated) { () -> UIImage? in
            // Skip decodes for views that scrolled away before their turn came up.
            guard !Task.isCancelled else { return nil }
            return ImageLoader.cgImage(at: url, maxPixel: maxPixel).map { UIImage(cgImage: $0) }
        }
        let image = await withTaskCancellationHandler {
            await work.value
        } onCancel: {
            work.cancel()
        }
        if let image, let cgImage = image.cgImage {
            cache.setObject(image, forKey: key, cost: cgImage.bytesPerRow * cgImage.height)
        }
        return image
    }

    static func image(from data: Data, maxPixel: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return thumbnail(of: source, maxPixel: maxPixel).map { UIImage(cgImage: $0) }
    }

    /// Upright (EXIF orientation applied) and no bigger than maxPixel on the long side.
    static func cgImage(at url: URL, maxPixel: Int) -> CGImage? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else { return nil }
        return thumbnail(of: source, maxPixel: maxPixel)
    }

    private static func thumbnail(of source: CGImageSource, maxPixel: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func key(_ url: URL, _ maxPixel: Int) -> NSString {
        "\(url.path)#\(maxPixel)" as NSString
    }
}

/// A photo that fills its frame. Parents set the size and clip.
struct ThumbnailView: View {
    let url: URL?
    let maxPixel: Int
    @State private var image: UIImage?

    init(url: URL?, maxPixel: Int = 300) {
        self.url = url
        self.maxPixel = maxPixel
        // Start from the cache so scrolling back up doesn't flash grey.
        _image = State(initialValue: url.flatMap { ImageLoader.shared.cachedImage(at: $0, maxPixel: maxPixel) })
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color(uiColor: .secondarySystemFill))
            }
        }
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            let loaded = await ImageLoader.shared.image(at: url, maxPixel: maxPixel)
            guard !Task.isCancelled else { return }
            image = loaded
        }
    }
}
