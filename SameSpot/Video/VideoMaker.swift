import AVFoundation
import CoreGraphics
import Foundation

enum VideoQuality: String, CaseIterable, Identifiable {
    case standard
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "Standard"
        case .high: return "High"
        }
    }

    var codec: AVVideoCodecType {
        switch self {
        case .standard: return .h264
        case .high: return .hevc
        }
    }

    /// Photos are 4:3, so the video is too.
    func size(landscape: Bool) -> CGSize {
        let long: CGFloat = self == .standard ? 1440 : 2880
        let short = long * 3 / 4
        return landscape ? CGSize(width: long, height: short) : CGSize(width: short, height: long)
    }

    func detail(landscape: Bool) -> String {
        let size = size(landscape: landscape)
        let dimensions = "\(Int(size.width)) × \(Int(size.height))"
        switch self {
        case .standard: return "\(dimensions), H.264. Plays anywhere."
        case .high: return "\(dimensions), HEVC. Sharper, best on Apple devices."
        }
    }
}

enum VideoMakerError: LocalizedError {
    case setupFailed
    case noReadablePhotos
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .setupFailed: return "The video writer wouldn't start."
        case .noReadablePhotos: return "None of the photos could be read."
        case .writeFailed: return "Writing the video stopped partway."
        }
    }
}

enum VideoMaker {
    /// Writes the photos, in order, one per frame, to an .mp4 in the temporary folder.
    static func write(
        urls: [URL],
        fps: Int,
        size: CGSize,
        codec: AVVideoCodecType,
        progress: @escaping (Double) -> Void
    ) async throws -> URL {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("Timelapse-\(UUID().uuidString)")
            .appendingPathExtension("mp4")
        let width = Int(size.width)
        let height = Int(size.height)

        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)

        // Every frame of a timelapse is a new picture with little carried over from the last,
        // so it needs more bits than ordinary video at the same size.
        let bitsPerPixel = codec == .hevc ? 0.2 : 0.35
        let bitrate = max(4_000_000, Int(Double(width * height * fps) * bitsPerPixel))
        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: bitrate,
            AVVideoExpectedSourceFrameRateKey: fps,
            AVVideoMaxKeyFrameIntervalKey: fps
        ]
        if codec == .h264 {
            compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
        }
        let settings: [String: Any] = [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: compression
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ]
        )

        guard writer.canAdd(input) else { throw VideoMakerError.setupFailed }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? VideoMakerError.setupFailed }
        writer.startSession(atSourceTime: .zero)

        var written = 0
        do {
            for (index, url) in urls.enumerated() {
                try Task.checkCancellation()
                // A photo that can't be read is skipped rather than ending the whole video.
                if let image = ImageLoader.cgImage(at: url, maxPixel: max(width, height)) {
                    while !input.isReadyForMoreMediaData {
                        try Task.checkCancellation()
                        try await Task.sleep(nanoseconds: 5_000_000)
                    }
                    guard let pool = adaptor.pixelBufferPool else { throw VideoMakerError.setupFailed }
                    var buffer: CVPixelBuffer?
                    CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer)
                    guard let buffer else { throw VideoMakerError.setupFailed }
                    draw(image, into: buffer, width: width, height: height)
                    let time = CMTime(value: CMTimeValue(written), timescale: CMTimeScale(fps))
                    guard adaptor.append(buffer, withPresentationTime: time) else {
                        throw writer.error ?? VideoMakerError.writeFailed
                    }
                    written += 1
                }
                progress(Double(index + 1) / Double(urls.count))
            }
        } catch {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: output)
            throw error
        }

        guard written > 0 else {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: output)
            throw VideoMakerError.noReadablePhotos
        }

        input.markAsFinished()
        // Without an end time the last photo gets no screen time at all.
        writer.endSession(atSourceTime: CMTime(value: CMTimeValue(written), timescale: CMTimeScale(fps)))
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting {
                continuation.resume()
            }
        }
        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: output)
            throw writer.error ?? VideoMakerError.writeFailed
        }
        return output
    }

    /// Scales the photo to fill the frame, cropping the overflow evenly.
    private static func draw(_ image: CGImage, into buffer: CVPixelBuffer, width: Int, height: Int) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return }

        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let imageWidth = CGFloat(image.width)
        let imageHeight = CGFloat(image.height)
        let scale = max(CGFloat(width) / imageWidth, CGFloat(height) / imageHeight)
        let drawWidth = imageWidth * scale
        let drawHeight = imageHeight * scale
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(
            x: (CGFloat(width) - drawWidth) / 2,
            y: (CGFloat(height) - drawHeight) / 2,
            width: drawWidth,
            height: drawHeight
        ))
    }
}

/// Runs a render in the background, publishes how far along it is, then plays the result on a loop.
/// It owns the temporary file, so the file goes away when the export sheet does.
/// Unchecked Sendable because every property is only read or written on the main queue.
final class TimelapseRenderer: ObservableObject, @unchecked Sendable {
    enum State: Equatable {
        case idle
        case rendering(Double)
        case finished(URL)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var task: Task<Void, Never>?

    deinit {
        task?.cancel()
        player?.pause()
        if case .finished(let url) = state {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func render(urls: [URL], fps: Int, size: CGSize, codec: AVVideoCodecType) {
        cancel()
        state = .rendering(0)
        // Holding self strongly is fine: a render takes seconds and the sheet owns the renderer.
        task = Task.detached(priority: .userInitiated) {
            do {
                let url = try await VideoMaker.write(urls: urls, fps: fps, size: size, codec: codec) { fraction in
                    DispatchQueue.main.async {
                        guard case .rendering = self.state else { return }
                        self.state = .rendering(fraction)
                    }
                }
                DispatchQueue.main.async {
                    guard case .rendering = self.state else {
                        // Cancelled while the file was being closed. Nobody wants it now.
                        try? FileManager.default.removeItem(at: url)
                        return
                    }
                    self.finish(with: url)
                }
            } catch is CancellationError {
                // Dismissed. Nothing to report.
            } catch {
                let message = error.localizedDescription
                DispatchQueue.main.async {
                    self.state = .failed(message)
                }
            }
        }
    }

    /// Stops a render in progress, or stops playback and throws away the finished file.
    func cancel() {
        task?.cancel()
        task = nil
        player?.pause()
        looper?.disableLooping()
        looper = nil
        player = nil
        if case .finished(let url) = state {
            try? FileManager.default.removeItem(at: url)
        }
        state = .idle
    }

    private func finish(with url: URL) {
        let queuePlayer = AVQueuePlayer()
        queuePlayer.isMuted = true
        looper = AVPlayerLooper(player: queuePlayer, templateItem: AVPlayerItem(url: url))
        player = queuePlayer
        state = .finished(url)
        queuePlayer.play()
    }
}
