import SwiftUI
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(SettingsKey.appearance) private var appearance: AppearanceSetting = .system

    @State private var notificationStatus: UNAuthorizationStatus?
    @State private var spaceUsed: String?
    @State private var showingPrivacyPolicy = false

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
                } header: {
                    Text("Reminders")
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
                    Button {
                        showingPrivacyPolicy = true
                    } label: {
                        Text("Privacy Policy")
                            .foregroundStyle(Color.primary)
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingPrivacyPolicy) {
                PrivacyPolicyView()
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
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}
