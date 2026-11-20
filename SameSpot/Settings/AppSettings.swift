import SwiftUI

/// UserDefaults keys for everything on the Settings tab. The camera reads the same keys,
/// so a change in either place shows up in both.
enum SettingsKey {
    static let showGrid = "showGrid"
    static let flash = "flash"
    static let timer = "timerSeconds"
    static let appearance = "appearance"
    static let reminderSound = "reminderSound"
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

/// What a reminder plays. iOS only lets an app use the system default or sounds it ships with,
/// so the other two are short files in SameSpot/Sounds.
enum ReminderSound: String, CaseIterable, Identifiable {
    case standard
    case chime
    case click
    case silent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "iPhone Default"
        case .chime: return "Chime"
        case .click: return "Click"
        case .silent: return "None"
        }
    }

    var fileName: String? {
        switch self {
        case .chime: return "chime.wav"
        case .click: return "click.wav"
        case .standard, .silent: return nil
        }
    }

    static var current: ReminderSound {
        UserDefaults.standard.string(forKey: SettingsKey.reminderSound).flatMap(ReminderSound.init(rawValue:)) ?? .standard
    }
}
