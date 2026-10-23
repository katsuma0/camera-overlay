import SwiftUI
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(SettingsKey.showGrid) private var showGrid = true
    @AppStorage(SettingsKey.flash) private var flash: FlashSetting = .off
    @AppStorage(SettingsKey.timer) private var timerSeconds = 0
    @AppStorage(SettingsKey.appearance) private var appearance: AppearanceSetting = .system
    @AppStorage(SettingsKey.haptics) private var haptics = true
    @AppStorage(SettingsKey.shutterBlink) private var shutterBlink = true

    @State private var notificationStatus: UNAuthorizationStatus?
    @State private var spaceUsed: String?

    private var photoCount: Int {
        store.projects.reduce(0) { $0 + $1.frames.count }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Grid", isOn: $showGrid)
                    Picker("Flash", selection: $flash) {
                        ForEach(FlashSetting.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    Picker("Timer", selection: $timerSeconds) {
                        ForEach(TimerSetting.options, id: \.self) { seconds in
                            Text(TimerSetting.title(seconds)).tag(seconds)
                        }
                    }
                } header: {
                    Text("Camera")
                } footer: {
                    Text("Flash changes the light from one photo to the next, so leave it off unless the spot is dark. The timer helps when the phone is propped on something.")
                }

                Section {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(AppearanceSetting.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("The camera stays dark either way.")
                }

                Section {
                    Toggle("Haptics", isOn: $haptics)
                    Toggle("Shutter Blink", isOn: $shutterBlink)
                } header: {
                    Text("Accessibility")
                } footer: {
                    Text("Shutter Blink darkens the screen for a moment when a photo is taken. It's skipped when Reduce Motion is on. Text size and bold text follow your iPhone's settings.")
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
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("Reminder times are set on each project's page.")
                }

                Section("Storage") {
                    LabeledContent("Projects", value: "\(store.projects.count)")
                    LabeledContent("Photos", value: "\(photoCount)")
                    LabeledContent("Space Used", value: spaceUsed ?? "Counting")
                }

                Section {
                    NavigationLink("About Same Spot") {
                        AboutView()
                    }
                }
            }
            .navigationTitle("Settings")
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

    private func refreshNotificationStatus() async {
        notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
}

struct AboutView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Image("Logo")
                        .resizable()
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .accessibilityHidden(true)
                    Text("Same Spot")
                        .font(.title2.weight(.semibold))
                    Text("Version \(version)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            Section {
                Text("I wanted a timelapse of my backyard changing through the seasons, but I couldn't frame the photo the same way twice. So I made this.")
                    .padding(.vertical, 4)
            }

            Section {
                if let site = URL(string: "https://katsuma.ca") {
                    Link(destination: site) {
                        Label("katsuma.ca", systemImage: "globe")
                    }
                }
            } footer: {
                Text("Made by Katsuma Onishi.")
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}
