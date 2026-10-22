import SwiftUI

struct ProjectsView: View {
    @EnvironmentObject private var store: ProjectStore
    @State private var showingNewProject = false

    var body: some View {
        NavigationStack {
            Group {
                if store.projects.isEmpty {
                    ContentUnavailableView {
                        Label("No Projects", systemImage: "square.stack")
                    } description: {
                        Text("Pick a spot you pass every day. A window, a garden bed, the corner of the street.")
                    } actions: {
                        Button("New Project") { showingNewProject = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List(store.projects) { project in
                        NavigationLink(value: project.id) {
                            ProjectRow(project: project)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Projects")
            .navigationDestination(for: UUID.self) { id in
                ProjectDetailView(projectID: id)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewProject = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New Project")
                }
            }
            .sheet(isPresented: $showingNewProject) {
                NewProjectView()
            }
        }
    }
}

struct ProjectRow: View {
    @EnvironmentObject private var store: ProjectStore
    let project: Project

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                ThumbnailView(url: store.templateURL(for: project), maxPixel: 200)
                if !project.hasTemplate {
                    Image(systemName: "camera")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(project.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(detailLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if project.hasTemplate && project.reminders.isOn {
                    Label(project.reminders.shortSummary, systemImage: "bell")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var detailLine: String {
        guard project.hasTemplate else { return "No original yet" }
        let count = project.frames.count
        let photos = count == 1 ? "1 photo" : "\(count) photos"
        guard let last = project.frames.last else { return photos }
        return "\(photos), last \(last.date.formatted(.relative(presentation: .named)))"
    }
}
