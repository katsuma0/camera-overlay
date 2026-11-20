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

    // MARK: Display copies

    /// A 12 MP HEIC takes tens of milliseconds to decode. A screen-size JPEG copy takes a few,
    /// which is what lets the viewer scrub through a project at full quality. Copies live in
    /// Caches, so iOS can clear them when space runs low and they get made again.
    static let displayPixel = 1800

    private static let displayFolder: URL = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Display", isDirectory: true)

    /// Photo file names are UUIDs, so the copy can share the name.
    private static func displayCopyURL(for url: URL) -> URL {
        displayFolder.appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".jpg")
    }

    /// Only from memory. Cheap enough to call while building a view.
    func cachedDisplayImage(for url: URL) -> UIImage? {
        cache.object(forKey: Self.key(url, Self.displayPixel))
    }

    /// From memory, or from the copy on disk if one has been made. A few milliseconds,
    /// so it's fine on the main thread while scrubbing.
    func readyDisplayImage(for url: URL) -> UIImage? {
        if let hit = cachedDisplayImage(for: url) { return hit }
        guard let image = Self.decodeDisplayCopy(for: url) else { return nil }
        remember(image, for: url)
        return image
    }

    /// Makes the copy first if there isn't one yet.
    func displayImage(for url: URL) async -> UIImage? {
        if let ready = readyDisplayImage(for: url) { return ready }
        let image = await Task.detached(priority: .userInitiated) {
            ImageLoader.makeDisplayCopy(for: url)
        }.value
        if let image { remember(image, for: url) }
        return image
    }

    /// Makes copies for every photo that doesn't have one, nearest first. Stops if cancelled.
    static func prepareDisplayCopies(for urls: [URL]) async {
        await Task.detached(priority: .utility) {
            for url in urls {
                if Task.isCancelled { return }
                if FileManager.default.fileExists(atPath: displayCopyURL(for: url).path) { continue }
                _ = makeDisplayCopy(for: url)
            }
        }.value
    }

    private func remember(_ image: UIImage, for url: URL) {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        cache.setObject(image, forKey: Self.key(url, Self.displayPixel), cost: cost)
    }

    private static func decodeDisplayCopy(for url: URL) -> UIImage? {
        // preparingForDisplay decodes now, instead of on the first draw.
        UIImage(contentsOfFile: displayCopyURL(for: url).path)?.preparingForDisplay()
    }

    private static func makeDisplayCopy(for url: URL) -> UIImage? {
        if let existing = decodeDisplayCopy(for: url) { return existing }
        guard let cgImage = cgImage(at: url, maxPixel: displayPixel) else { return nil }
        let image = UIImage(cgImage: cgImage)
        if let data = image.jpegData(compressionQuality: 0.9) {
            try? FileManager.default.createDirectory(at: displayFolder, withIntermediateDirectories: true)
            try? data.write(to: displayCopyURL(for: url), options: .atomic)
        }
        return image
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
