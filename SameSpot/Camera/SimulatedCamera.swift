import UIKit

/// Stand-in for the camera in the simulator, which doesn't have one. Draws a small backyard
/// so the whole flow (original, overlay, library, video) can be tried without a phone.
enum SimulatedCamera {
    static let previewImage: UIImage = scene(
        size: CGSize(width: 900, height: 1200),
        progress: 0.15,
        offset: .zero,
        date: nil
    )

    static func capture(angle: Double) -> Result<CapturedPhoto, Error> {
        let now = Date()
        let second = Calendar.current.component(.second, from: now)
        guard let photo = photo(angle: angle, progress: Double(second) / 59, seed: second, date: now) else {
            return .failure(CameraError.noPhotoData)
        }
        return .success(photo)
    }

    static func photo(angle: Double, progress: Double, seed: Int, date: Date) -> CapturedPhoto? {
        // Nobody holds a phone in exactly the same place twice. Nudge each shot a little.
        let offset = CGPoint(x: CGFloat((seed * 37) % 17 - 8), y: CGFloat((seed * 53) % 13 - 6))
        let image = scene(size: CGSize(width: 1200, height: 1600), progress: progress, offset: offset, date: date)
        guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
        return CapturedPhoto(data: data, fileExtension: "jpg", angle: angle, date: date)
    }

    static func scene(size: CGSize, progress: Double, offset: CGPoint, date: Date?) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let w = size.width
            let h = size.height
            let p = CGFloat(min(max(progress, 0), 1))

            cg.translateBy(x: offset.x, y: offset.y)

            let sky = [
                UIColor(red: 0.45, green: 0.68, blue: 0.93, alpha: 1).cgColor,
                UIColor(red: 0.86, green: 0.92, blue: 0.97, alpha: 1).cgColor
            ] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: sky, locations: [0, 1]) {
                cg.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: -40),
                    end: CGPoint(x: 0, y: h * 0.7),
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
                )
            }

            // The sun drifts across over the life of the project.
            UIColor(red: 1, green: 0.85, blue: 0.45, alpha: 1).setFill()
            cg.fillEllipse(in: CGRect(x: w * (0.1 + 0.62 * p), y: h * 0.09, width: w * 0.13, height: w * 0.13))

            UIColor(white: 0.94, alpha: 1).setFill()
            for i in 0..<14 {
                cg.fill(CGRect(x: -40 + CGFloat(i) * w * 0.085, y: h * 0.55, width: w * 0.05, height: h * 0.16))
            }
            cg.fill(CGRect(x: -40, y: h * 0.6, width: w + 80, height: h * 0.02))

            UIColor(red: 0.33, green: 0.55, blue: 0.28, alpha: 1).setFill()
            cg.fill(CGRect(x: -40, y: h * 0.7, width: w + 80, height: h * 0.35))

            UIColor(red: 0.36, green: 0.25, blue: 0.17, alpha: 1).setFill()
            cg.fill(CGRect(x: w * 0.46, y: h * 0.38, width: w * 0.08, height: h * 0.36))

            leafColor(p).setFill()
            let blobs: [(CGFloat, CGFloat, CGFloat)] = [
                (0.5, 0.3, 0.24), (0.32, 0.38, 0.16), (0.68, 0.38, 0.16), (0.42, 0.22, 0.14), (0.6, 0.22, 0.14)
            ]
            for (x, y, r) in blobs {
                cg.fillEllipse(in: CGRect(x: w * x - w * r, y: h * y - w * r, width: w * r * 2, height: w * r * 2))
            }

            if let date {
                let text = date.formatted(date: .abbreviated, time: .shortened) as NSString
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.monospacedDigitSystemFont(ofSize: w * 0.035, weight: .semibold),
                    .foregroundColor: UIColor.white
                ]
                text.draw(at: CGPoint(x: w * 0.05, y: h * 0.92), withAttributes: attributes)
            }
        }
    }

    /// Green, then orange, then red.
    private static func leafColor(_ p: CGFloat) -> UIColor {
        let stops: [(CGFloat, CGFloat, CGFloat)] = [(0.27, 0.52, 0.20), (0.90, 0.55, 0.12), (0.78, 0.16, 0.10)]
        let scaled = p * CGFloat(stops.count - 1)
        let i = min(Int(scaled), stops.count - 2)
        let t = scaled - CGFloat(i)
        let a = stops[i]
        let b = stops[i + 1]
        return UIColor(
            red: a.0 + (b.0 - a.0) * t,
            green: a.1 + (b.1 - a.1) * t,
            blue: a.2 + (b.2 - a.2) * t,
            alpha: 1
        )
    }
}
