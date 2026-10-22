import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        TabView(selection: $router.tab) {
            CameraTab()
                .tabItem { Label("Camera", systemImage: "camera.fill") }
                .tag(AppRouter.Tab.camera)
            LibraryView()
                .tabItem { Label("Library", systemImage: "photo.on.rectangle.angled") }
                .tag(AppRouter.Tab.library)
            ProjectsView()
                .tabItem { Label("Projects", systemImage: "square.stack.fill") }
                .tag(AppRouter.Tab.projects)
        }
        .onChange(of: store.reminderSignature, initial: true) {
            NotificationScheduler.sync(store.projects)
        }
    }
}
