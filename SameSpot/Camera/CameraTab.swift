import SwiftUI

struct CameraTab: View {
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var router: AppRouter
    @State private var showingNewProject = false

    /// Falls back to the newest project when nothing is picked or the pick was deleted.
    private var project: Project? {
        store.project(router.cameraProjectID) ?? store.projects.first
    }

    var body: some View {
        NavigationStack {
            Group {
                if let project {
                    CaptureView(project: project, showingNewProject: $showingNewProject)
                } else {
                    emptyState
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .toolbarBackground(Color.black, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.dark, for: .tabBar)
        .sheet(isPresented: $showingNewProject) {
            NewProjectView()
        }
        .onChange(of: router.reminderTapCount) {
            showingNewProject = false
        }
    }

    private var emptyState: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ContentUnavailableView {
                Label("No Projects Yet", systemImage: "camera.viewfinder")
            } description: {
                Text("A project is one spot you keep coming back to. You take an original photo, then every photo after lines up with it.")
            } actions: {
                Button("New Project") { showingNewProject = true }
                    .buttonStyle(.borderedProminent)
            }
        }
        .environment(\.colorScheme, .dark)
        .navigationTitle("Camera")
    }
}
