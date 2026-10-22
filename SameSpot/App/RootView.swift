import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var router: AppRouter
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SettingsKey.appearance) private var appearance: AppearanceSetting = .system

    var body: some View {
        TabView(selection: $router.tab) {
            ProjectsView()
                .tabItem { Label("Projects", systemImage: "square.stack.fill") }
                .tag(AppRouter.Tab.projects)
            CameraTab()
                .tabItem { Label("Camera", systemImage: "camera.fill") }
                .tag(AppRouter.Tab.camera)
            LibraryView()
                .tabItem { Label("Library", systemImage: "photo.on.rectangle.angled") }
                .tag(AppRouter.Tab.library)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(AppRouter.Tab.settings)
        }
        .onChange(of: appearance, initial: true) {
            let style = appearance.interfaceStyle
            for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                for window in scene.windows {
                    window.overrideUserInterfaceStyle = style
                }
            }
        }
        .onChange(of: store.reminderSignature, initial: true) {
            NotificationScheduler.sync(store.projects)
        }
        // iOS drops reminders added before permission is granted. The permission alert and a
        // trip to Settings both send the app inactive, so coming back active is the moment to retry.
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                NotificationScheduler.sync(store.projects)
            }
        }
    }
}
