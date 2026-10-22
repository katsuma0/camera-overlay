import Foundation

/// Which tab is showing and which project the camera is pointed at.
/// It's a singleton because reminder taps arrive from outside the SwiftUI tree.
final class AppRouter: ObservableObject {
    static let shared = AppRouter()

    enum Tab: Hashable {
        case projects, camera, library, settings
    }

    @Published var tab: Tab = .projects {
        // Leaving the camera abandons a retake. Otherwise tomorrow's reminder would land in it.
        didSet { if tab != .camera { retakeProjectID = nil } }
    }
    @Published var cameraProjectID: UUID? = nil {
        didSet { UserDefaults.standard.set(cameraProjectID?.uuidString, forKey: Self.cameraProjectKey) }
    }
    /// Set when someone asks to reshoot a project's original photo.
    @Published var retakeProjectID: UUID? = nil
    /// Goes up by one on every reminder tap, so open sheets and viewers know to get out of the way.
    @Published private(set) var reminderTapCount = 0

    private static let cameraProjectKey = "cameraProjectID"

    private init() {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: Self.cameraProjectKey) {
            cameraProjectID = UUID(uuidString: raw)
        }
        // Launch argument for screenshots and testing, e.g. -launchTab library
        switch defaults.string(forKey: "launchTab") {
        case "camera": tab = .camera
        case "library": tab = .library
        case "settings": tab = .settings
        default: tab = .projects
        }
    }

    func openCamera(for projectID: UUID) {
        retakeProjectID = nil
        cameraProjectID = projectID
        tab = .camera
    }

    func openFromReminder(_ projectID: UUID) {
        reminderTapCount += 1
        openCamera(for: projectID)
    }

    func retakeOriginal(for projectID: UUID) {
        openCamera(for: projectID)
        retakeProjectID = projectID
    }
}
