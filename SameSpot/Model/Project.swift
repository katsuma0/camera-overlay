import Foundation

struct Project: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var createdAt = Date()
    /// File name of the original photo inside the project folder. Nil until it's taken.
    var templateFile: String?
    var templateDate: Date?
    /// Rotation every photo in the project is captured at. The original sets it, so a project
    /// never ends up with a mix of portrait and landscape frames.
    var captureAngle: Double = 90
    var overlayOpacity: Double = 0.35
    var overlaySource: OverlaySource = .original
    /// Camera zoom for this project, like 0.5 or 2. Optional so projects saved before zoom
    /// existed still load.
    var zoom: Double?
    var reminders = ReminderSchedule()
    var frames: [Frame] = []

    var hasTemplate: Bool { templateFile != nil }
    var isLandscape: Bool { Int(captureAngle.rounded()) % 180 == 0 }
}

struct Frame: Identifiable, Codable, Hashable {
    var id = UUID()
    var date: Date
    var file: String
}

/// What gets ghosted over the camera. The original is the point of the app, but lining up
/// with yesterday's photo is easier once the scene has changed a lot.
enum OverlaySource: String, Codable, CaseIterable {
    case original
    case latest
}
