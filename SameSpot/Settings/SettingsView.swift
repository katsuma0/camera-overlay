import AudioToolbox
import SwiftUI
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(SettingsKey.appearance) private var appearance: AppearanceSetting = .system
    @AppStorage(SettingsKey.reminderSound) private var reminderSound: ReminderSound = .standard

    @State private var notificationStatus: UNAuthorizationStatus?
    @State private var spaceUsed: String?
    @State private var infoSheet: InfoPage?

    private var photoCount: Int {
        store.projects.reduce(0) { $0 + $1.frames.count }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(AppearanceSetting.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Section {
                    Button {
                        notificationsTapped()
                    } label: {
                        HStack {
                            Text("Notifications")
                                .foregroundStyle(Color.primary)
                            Spacer()
                            Text(notificationLabel)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Picker("Sound", selection: $reminderSound) {
                        ForEach(ReminderSound.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                } header: {
                    Text("Reminders")
                }
                // Pending reminders keep the sound they were made with, so rebuild them.
                .onChange(of: reminderSound) {
                    NotificationScheduler.sync(store.projects)
                    preview(reminderSound)
                }

                Section("Storage") {
                    LabeledContent("Projects", value: "\(store.projects.count)")
                    LabeledContent("Photos", value: "\(photoCount)")
                    LabeledContent("Space Used", value: spaceUsed ?? "Counting")
                }

                Section {
                    infoRow("How to Use", sheet: .howToUse)
                    infoRow("About Same Spot", sheet: .about)
                    infoRow("Privacy Policy", sheet: .privacy)
                }
            }
            .navigationTitle("Settings")
            .sheet(item: $infoSheet) { sheet in
                switch sheet {
                case .howToUse: HowToUseView()
                case .about: AboutView()
                case .privacy: PrivacyPolicyView()
                }
            }
            // Re-checked on return from the iPhone's Settings app.
            .task(id: scenePhase) {
                if scenePhase == .active {
                    await refreshNotificationStatus()
                }
            }
            .task(id: photoCount) {
                let root = store.rootURL
                let bytes = await Task.detached(priority: .utility) {
                    ProjectStore.diskUsage(at: root)
                }.value
                spaceUsed = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            }
        }
    }

    private var notificationLabel: String {
        guard let notificationStatus else { return "" }
        switch notificationStatus {
        case .notDetermined: return "Not Asked"
        case .denied: return "Off"
        case .authorized, .provisional, .ephemeral: return "On"
        @unknown default: return ""
        }
    }

    /// Asks the first time. After that iOS only lets the user change it in the Settings app.
    private func notificationsTapped() {
        if notificationStatus == .notDetermined {
            let store = self.store
            NotificationScheduler.requestAuthorization { granted in
                if granted { NotificationScheduler.sync(store.projects) }
                Task { await refreshNotificationStatus() }
            }
        } else if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
            openURL(url)
        }
    }

    private enum InfoPage: String, Identifiable {
        case howToUse, about, privacy
        var id: String { rawValue }
    }

    private func infoRow(_ title: String, sheet: InfoPage) -> some View {
        Button {
            infoSheet = sheet
        } label: {
            Text(title)
                .foregroundStyle(Color.primary)
        }
    }

    /// Plays the choice once so you know what you picked.
    private func preview(_ sound: ReminderSound) {
        switch sound {
        case .standard:
            AudioServicesPlaySystemSound(1007)
        case .silent:
            break
        case .chime, .click:
            guard let name = sound.fileName,
                  let url = Bundle.main.url(forResource: name, withExtension: nil) else { return }
            var id: SystemSoundID = 0
            AudioServicesCreateSystemSoundID(url as CFURL, &id)
            AudioServicesPlaySystemSoundWithCompletion(id) {
                AudioServicesDisposeSystemSoundID(id)
            }
        }
    }

    private func refreshNotificationStatus() async {
        notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
}
