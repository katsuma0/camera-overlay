import SwiftUI

private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

/// Every photo from every project, newest first, one section per project.
struct LibraryView: View {
    @EnvironmentObject private var store: ProjectStore
    @State private var viewerItem: ViewerItem?

    private var projectsWithPhotos: [Project] {
        store.projects.filter { !$0.frames.isEmpty }
    }

    var body: some View {
        NavigationStack {
            Group {
                if projectsWithPhotos.isEmpty {
                    ContentUnavailableView(
                        "No Photos Yet",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("Photos you take show up here, grouped by project.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: gridColumns, spacing: 2, pinnedViews: [.sectionHeaders]) {
                            ForEach(projectsWithPhotos) { project in
                                Section {
                                    ForEach(project.frames.reversed()) { frame in
                                        Button {
                                            viewerItem = ViewerItem(projectID: project.id, frameID: frame.id)
                                        } label: {
                                            FrameCell(url: store.url(for: frame, in: project))
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel(frame.date.formatted(date: .abbreviated, time: .shortened))
                                    }
                                } header: {
                                    LibrarySectionHeader(project: project)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Library")
            .fullScreenCover(item: $viewerItem) { item in
                PhotoViewer(projectID: item.projectID, startFrameID: item.frameID)
            }
        }
    }
}

/// One project's photos, reached from the project screen.
struct ProjectPhotosView: View {
    let projectID: UUID

    @EnvironmentObject private var store: ProjectStore
    @State private var viewerItem: ViewerItem?

    var body: some View {
        Group {
            if let project = store.project(projectID), !project.frames.isEmpty {
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 2) {
                        ForEach(project.frames.reversed()) { frame in
                            Button {
                                viewerItem = ViewerItem(projectID: project.id, frameID: frame.id)
                            } label: {
                                FrameCell(url: store.url(for: frame, in: project))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(frame.date.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                }
            } else {
                ContentUnavailableView("No Photos", systemImage: "photo")
            }
        }
        .navigationTitle("Photos")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $viewerItem) { item in
            PhotoViewer(projectID: item.projectID, startFrameID: item.frameID)
        }
    }
}

struct FrameCell: View {
    let url: URL

    var body: some View {
        Color(uiColor: .secondarySystemFill)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                ThumbnailView(url: url, maxPixel: 300)
            }
            .clipped()
            .contentShape(Rectangle())
    }
}

struct LibrarySectionHeader: View {
    let project: Project

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(project.name)
                .font(.headline)
            Spacer()
            Text(project.frames.count == 1 ? "1 photo" : "\(project.frames.count) photos")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}
