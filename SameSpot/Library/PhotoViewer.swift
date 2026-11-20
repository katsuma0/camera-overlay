import SwiftUI

struct ViewerItem: Identifiable, Hashable {
    let projectID: UUID
    let frameID: UUID
    var id: UUID { frameID }
}

/// Full screen, swipe or scrub between a project's photos, share or delete one.
/// Pages run in the library's sort order, so swiping goes the same way as the grid.
struct PhotoViewer: View {
    let projectID: UUID

    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(LibraryOrder.key) private var newestFirst = true
    @State private var selection: UUID
    @State private var confirmingDelete = false

    init(projectID: UUID, startFrameID: UUID) {
        self.projectID = projectID
        _selection = State(initialValue: startFrameID)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let project = store.project(projectID), !project.frames.isEmpty {
                    pager(project)
                } else {
                    Color.black
                }
            }
            .background(Color.black.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar, .bottomBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func pager(_ project: Project) -> some View {
        let frames = project.orderedFrames(newestFirst: newestFirst)
        let index = frames.firstIndex { $0.id == selection } ?? 0
        let current = frames[index]
        let scrubIndex = Binding<Int>(
            get: { index },
            set: { selection = frames[min(max($0, 0), frames.count - 1)].id }
        )

        return VStack(spacing: 0) {
            TabView(selection: $selection) {
                ForEach(frames) { frame in
                    FullPhotoView(url: store.url(for: frame, in: project))
                        .tag(frame.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            if frames.count > 1 {
                FrameScrubber(count: frames.count, index: scrubIndex)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
            }
        }
        // Make the fast-loading copies in the background, starting from the photo on screen,
        // so scrubbing anywhere in the project shows full quality.
        .task(id: project.frames.count) {
            let ordered = frames.indices.sorted { abs($0 - index) < abs($1 - index) }
            await ImageLoader.prepareDisplayCopies(for: ordered.map { store.url(for: frames[$0], in: project) })
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(current.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.subheadline.weight(.semibold))
                    Text("\(current.date.formatted(date: .omitted, time: .shortened)), \(index + 1) of \(frames.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            ToolbarItemGroup(placement: .bottomBar) {
                ShareLink(item: store.url(for: current, in: project)) {
                    Image(systemName: "square.and.arrow.up")
                }
                Spacer()
                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Delete Photo")
            }
        }
        .confirmationDialog("Delete this photo?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Photo", role: .destructive) {
                delete(current, in: project)
            }
        } message: {
            Text("It comes out of the project and any video you make after this.")
        }
    }

    private func delete(_ frame: Frame, in project: Project) {
        let frames = project.orderedFrames(newestFirst: newestFirst)
        guard let index = frames.firstIndex(of: frame) else { return }
        if frames.count == 1 {
            store.deleteFrame(frame.id, in: project.id)
            dismiss()
            return
        }
        // Land on the next photo in the current order, or the previous one if this was the last.
        let neighbour = index + 1 < frames.count ? frames[index + 1] : frames[index - 1]
        selection = neighbour.id
        store.deleteFrame(frame.id, in: project.id)
    }
}

struct FullPhotoView: View {
    let url: URL
    @State private var image: UIImage?

    init(url: URL) {
        self.url = url
        _image = State(initialValue: ImageLoader.shared.cachedDisplayImage(for: url))
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // The copy on disk decodes in a few milliseconds, so take it straight away
            // rather than flashing a placeholder while scrubbing.
            if image == nil {
                image = ImageLoader.shared.readyDisplayImage(for: url)
            }
        }
        .task(id: url) {
            guard image == nil else { return }
            let loaded = await ImageLoader.shared.displayImage(for: url)
            if !Task.isCancelled {
                image = loaded
            }
        }
        // Pages keep their state, so let go of the image once this one is off screen.
        .onDisappear {
            image = nil
        }
    }
}
