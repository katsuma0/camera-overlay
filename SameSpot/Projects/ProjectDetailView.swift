import SwiftUI

struct ProjectDetailView: View {
    let projectID: UUID

    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss

    @State private var showingVideo = false
    @State private var showingRename = false
    @State private var draftName = ""
    @State private var confirmingDelete = false

    var body: some View {
        if let project = store.project(projectID) {
            content(project)
        } else {
            ContentUnavailableView("Project Deleted", systemImage: "trash")
        }
    }

    private func content(_ project: Project) -> some View {
        List {
            Section {
                ZStack {
                    if project.hasTemplate {
                        ThumbnailView(url: store.templateURL(for: project), maxPixel: 1200)
                    } else {
                        Color(uiColor: .secondarySystemFill)
                        VStack(spacing: 8) {
                            Image(systemName: "camera.viewfinder")
                                .font(.largeTitle)
                            Text("No original yet")
                                .font(.subheadline)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 280)
                .clipped()
                .listRowInsets(EdgeInsets())
            } footer: {
                if let date = project.templateDate {
                    Text("Original taken \(date.formatted(date: .abbreviated, time: .shortened))")
                }
            }

            Section {
                Button {
                    router.openCamera(for: project.id)
                } label: {
                    Label(project.hasTemplate ? "Take Today's Photo" : "Take the Original", systemImage: "camera")
                }
                Button {
                    showingVideo = true
                } label: {
                    Label("Make Timelapse", systemImage: "film")
                }
                .disabled(project.frames.count < 2)
            } footer: {
                if project.frames.count < 2 {
                    Text("Take at least two photos and there's a video to make.")
                }
            }

            Section {
                NavigationLink {
                    ProjectPhotosView(projectID: project.id)
                } label: {
                    LabeledContent("Photos", value: "\(project.frames.count)")
                }
                NavigationLink {
                    RemindersView(projectID: project.id, initial: project.reminders)
                } label: {
                    LabeledContent("Reminders", value: project.reminders.shortSummary)
                }
                LabeledContent("Started", value: project.createdAt.formatted(date: .abbreviated, time: .omitted))
            }

            Section {
                Button("Rename") {
                    draftName = project.name
                    showingRename = true
                }
                if project.hasTemplate {
                    Button("Retake Original") {
                        router.retakeOriginal(for: project.id)
                    }
                }
                Button("Delete Project", role: .destructive) {
                    confirmingDelete = true
                }
            } footer: {
                if project.hasTemplate {
                    Text("Retaking the original changes the guide. The photos you already have stay.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingVideo) {
            VideoExportView(projectID: project.id)
        }
        .alert("Rename Project", isPresented: $showingRename) {
            TextField("Name", text: $draftName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                store.rename(project.id, to: draftName)
            }
        }
        // A reminder tap switches to the camera. Anything open here would sit on top of it.
        // The video sheet closes itself so it can stop its render first.
        .onChange(of: router.reminderTapCount) {
            showingRename = false
            confirmingDelete = false
        }
        .confirmationDialog("Delete \(project.name)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button(deleteTitle(project), role: .destructive) {
                store.deleteProject(project.id)
                dismiss()
            }
        } message: {
            Text("This can't be undone.")
        }
    }

    private func deleteTitle(_ project: Project) -> String {
        switch project.frames.count {
        case 0: return "Delete Project"
        case 1: return "Delete Project and 1 Photo"
        default: return "Delete Project and \(project.frames.count) Photos"
        }
    }
}
