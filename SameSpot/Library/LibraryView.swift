import SwiftUI

private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

/// The library's sort order, shared by the grids and the full screen viewer so swiping
/// moves through photos in the same order they sit in the grid.
enum LibraryOrder {
    static let key = "libraryNewestFirst"
}

extension Project {
    func orderedFrames(newestFirst: Bool) -> [Frame] {
        newestFirst ? Array(frames.reversed()) : frames
    }
}

/// Every photo from every project, one section per project.
struct LibraryView: View {
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var router: AppRouter
    @AppStorage(LibraryOrder.key) private var newestFirst = true
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
                                    FrameCells(project: project, newestFirst: newestFirst) { frame in
                                        viewerItem = ViewerItem(projectID: project.id, frameID: frame.id)
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
            #if DEBUG
            // Launch argument so CI can screenshot the viewer without tapping anything.
            .onAppear {
                guard ProcessInfo.processInfo.arguments.contains("-openFirstPhoto"), viewerItem == nil,
                      let project = projectsWithPhotos.first,
                      let frame = project.orderedFrames(newestFirst: newestFirst).first else { return }
                viewerItem = ViewerItem(projectID: project.id, frameID: frame.id)
            }
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    SortMenu(newestFirst: $newestFirst)
                }
            }
            .fullScreenCover(item: $viewerItem) { item in
                PhotoViewer(projectID: item.projectID, startFrameID: item.frameID)
            }
            .onChange(of: router.reminderTapCount) {
                viewerItem = nil
            }
        }
    }
}

/// One project's photos, reached from the project screen.
struct ProjectPhotosView: View {
    let projectID: UUID

    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var router: AppRouter
    @AppStorage(LibraryOrder.key) private var newestFirst = true
    @State private var viewerItem: ViewerItem?

    var body: some View {
        Group {
            if let project = store.project(projectID), !project.frames.isEmpty {
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 2) {
                        FrameCells(project: project, newestFirst: newestFirst) { frame in
                            viewerItem = ViewerItem(projectID: project.id, frameID: frame.id)
                        }
                    }
                }
            } else {
                ContentUnavailableView("No Photos", systemImage: "photo")
            }
        }
        .navigationTitle("Photos")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                SortMenu(newestFirst: $newestFirst)
            }
        }
        .fullScreenCover(item: $viewerItem) { item in
            PhotoViewer(projectID: item.projectID, startFrameID: item.frameID)
        }
        .onChange(of: router.reminderTapCount) {
            viewerItem = nil
        }
    }
}

/// A project's photos as grid cells, in library order.
struct FrameCells: View {
    let project: Project
    let newestFirst: Bool
    let onSelect: (Frame) -> Void

    @EnvironmentObject private var store: ProjectStore

    var body: some View {
        ForEach(project.orderedFrames(newestFirst: newestFirst)) { frame in
            Button {
                onSelect(frame)
            } label: {
                FrameCell(url: store.url(for: frame, in: project), date: frame.date)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(frame.date.formatted(date: .abbreviated, time: .shortened))
        }
    }
}

struct SortMenu: View {
    @Binding var newestFirst: Bool

    var body: some View {
        Menu {
            Picker("Sort", selection: $newestFirst) {
                Label("Newest First", systemImage: "arrow.down").tag(true)
                Label("Oldest First", systemImage: "arrow.up").tag(false)
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .accessibilityLabel("Sort, \(newestFirst ? "newest first" : "oldest first")")
    }
}

struct FrameCell: View {
    let url: URL
    var date: Date? = nil

    var body: some View {
        Color(uiColor: .secondarySystemFill)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                ThumbnailView(url: url, maxPixel: 300)
            }
            .overlay(alignment: .bottomLeading) {
                if let date {
                    Text(Self.label(for: date))
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.horizontal, 6)
                        .padding(.top, 10)
                        .padding(.bottom, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // A soft dark fade so the date reads on bright skies and snow.
                        .background(
                            LinearGradient(
                                colors: [Color.black.opacity(0), Color.black.opacity(0.55)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .accessibilityHidden(true)
                }
            }
            .clipped()
            .contentShape(Rectangle())
    }

    /// "Oct 22, 8:02 AM" this year, "Oct 22, 2025" for older photos.
    static func label(for date: Date) -> String {
        if Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year) {
            let day = date.formatted(.dateTime.month(.abbreviated).day())
            return "\(day), \(date.formatted(date: .omitted, time: .shortened))"
        }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
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
