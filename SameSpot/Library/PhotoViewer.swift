import SwiftUI

struct ViewerItem: Identifiable, Hashable {
    let projectID: UUID
    let frameID: UUID
    var id: UUID { frameID }
}

/// Full screen, swipe between a project's photos, share or delete one.
struct PhotoViewer: View {
    let projectID: UUID

    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
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
        let frames = project.frames
        let index = frames.firstIndex { $0.id == selection } ?? 0
        let current = frames[index]

        return TabView(selection: $selection) {
            ForEach(frames) { frame in
                FullPhotoView(url: store.url(for: frame, in: project))
                    .tag(frame.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
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
        let frames = project.frames
        guard let index = frames.firstIndex(of: frame) else { return }
        if frames.count == 1 {
            store.deleteFrame(frame.id, in: project.id)
            dismiss()
            return
        }
        // Land on the next photo, or the previous one if this was the last.
        let neighbour = index + 1 < frames.count ? frames[index + 1] : frames[index - 1]
        selection = neighbour.id
        store.deleteFrame(frame.id, in: project.id)
    }
}

struct FullPhotoView: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: url) {
            image = await ImageLoader.shared.image(at: url, maxPixel: 2400)
        }
    }
}
