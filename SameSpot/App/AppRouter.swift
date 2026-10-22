import Foundation

/// Which tab is showing and which project the camera is pointed at.
/// It's a singleton because reminder taps arrive from outside the SwiftUI tree.
final class AppRouter: ObservableObject {
    static let shared = AppRouter()

    enum Tab: Hashable {
        case camera, library, projects
    }

    @Published var tab: Tab = .camera
    @Published var cameraProjectID: UUID? = nil {
        didSet { UserDefaults.standard.set(cameraProjectID?.uuidString, forKey: Self.cameraProjectKey) }
    }
    /// Set when someone asks to reshoot a project's original photo.
    @Published var retakeProjectID: UUID? = nil

    private static let cameraProjectKey = "cameraProjectID"

    private init() {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: Self.cameraProjectKey) {
            cameraProjectID = UUID(uuidString: raw)
        }
        // Launch argument for screenshots and testing, e.g. -launchTab library
        switch defaults.string(forKey: "launchTab") {
        case "library": tab = .library
        case "projects": tab = .projects
        default: tab = .camera
        }
    }

    func openCamera(for projectID: UUID) {
        cameraProjectID = projectID
        tab = .camera
    }

    func retakeOriginal(for projectID: UUID) {
        retakeProjectID = projectID
        openCamera(for: projectID)
    }
}
