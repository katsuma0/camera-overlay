import SwiftUI

/// UserDefaults keys for everything on the Settings tab. The camera reads the same keys,
/// so a change in either place shows up in both.
enum SettingsKey {
    static let showGrid = "showGrid"
    static let flash = "flash"
    static let timer = "timerSeconds"
    static let appearance = "appearance"
    static let haptics = "haptics"
    static let shutterBlink = "shutterBlink"
}

enum FlashSetting: String, CaseIterable, Identifiable {
    case off
    case auto
    case on

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .auto: return "Auto"
        case .on: return "On"
        }
    }

    var symbol: String {
        switch self {
        case .off: return "bolt.slash.fill"
        case .auto: return "bolt.badge.a.fill"
        case .on: return "bolt.fill"
        }
    }

    /// Order the camera's flash button steps through, same as the iPhone camera.
    var next: FlashSetting {
        switch self {
        case .off: return .auto
        case .auto: return .on
        case .on: return .off
        }
    }
}

/// Self-timer lengths in seconds. Zero is off.
enum TimerSetting {
    static let options = [0, 3, 10]

    static func title(_ seconds: Int) -> String {
        seconds == 0 ? "Off" : "\(seconds) Seconds"
    }

    static func next(after seconds: Int) -> Int {
        let index = options.firstIndex(of: seconds) ?? 0
        return options[(index + 1) % options.count]
    }
}

enum AppearanceSetting: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// Set on the window rather than with preferredColorScheme, which can stick on Light or Dark
    /// after switching back to System until the app relaunches.
    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }
}
