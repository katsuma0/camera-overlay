import AVKit
import Photos
import SwiftUI

struct VideoExportView: View {
    let projectID: UUID

    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("videoFPS") private var fps = 12
    @AppStorage("videoQuality") private var quality: VideoQuality = .standard
    @StateObject private var renderer = TimelapseRenderer()
    @State private var saveStatus: SaveStatus = .idle

    private enum SaveStatus: Equatable {
        case idle
        case saving
        case saved
        case failed(String)
    }

    private static let speeds = [6, 12, 24, 30]

    private var isRendering: Bool {
        if case .rendering = renderer.state { return true }
        return false
    }

    private var isFinished: Bool {
        if case .finished = renderer.state { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Group {
                if let project = store.project(projectID) {
                    content(project)
                } else {
                    ContentUnavailableView("Project Deleted", systemImage: "trash")
                }
            }
            .navigationTitle("Timelapse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isFinished ? "Done" : "Cancel") {
                        renderer.cancel()
                        dismiss()
                    }
                }
            }
        }
        // Swiping away mid-render would leave it running with nothing to show it.
        .interactiveDismissDisabled(isRendering)
    }

    @ViewBuilder
    private func content(_ project: Project) -> some View {
        switch renderer.state {
        case .idle:
            setupForm(project)
        case .rendering(let fraction):
            VStack(spacing: 14) {
                ProgressView(value: fraction)
                    .frame(maxWidth: 240)
                Text("Putting \(project.frames.count) photos together. \(Int(fraction * 100))%")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .finished(let url):
            result(url, project: project)
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't Make the Video", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { renderer.cancel() }
            }
        }
    }

    private func setupForm(_ project: Project) -> some View {
        let count = project.frames.count
        let seconds = Double(count) / Double(max(fps, 1))

        return Form {
            Section {
                LabeledContent("Photos", value: "\(count)")
                LabeledContent("Length", value: Self.lengthText(seconds))
            }

            Section {
                Picker("Photos per Second", selection: $fps) {
                    ForEach(Self.speeds, id: \.self) { speed in
                        Text("\(speed)").tag(speed)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Photos per Second")
            } footer: {
                Text("12 is a good place to start. Go higher once a project has hundreds of photos so the video doesn't drag.")
            }

            Section {
                Picker("Quality", selection: $quality) {
                    ForEach(VideoQuality.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Quality")
            } footer: {
                Text(quality.detail(landscape: project.isLandscape))
            }

            Section {
                Button {
                    saveStatus = .idle
                    renderer.render(
                        urls: project.frames.map { store.url(for: $0, in: project) },
                        fps: max(fps, 1),
                        size: quality.size(landscape: project.isLandscape),
                        codec: quality.codec
                    )
                } label: {
                    Text("Make Video")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .disabled(count < 2)
            }
        }
    }

    private func result(_ url: URL, project: Project) -> some View {
        VStack(spacing: 20) {
            if let player = renderer.player {
                VideoPlayer(player: player)
                    .aspectRatio(project.isLandscape ? 4.0 / 3.0 : 3.0 / 4.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .frame(maxHeight: .infinity)
            } else {
                Spacer()
            }

            HStack(spacing: 12) {
                ShareLink(item: url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    Task { await saveToPhotos(url) }
                } label: {
                    Label(saveTitle, systemImage: saveStatus == .saved ? "checkmark" : "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(saveStatus == .saving || saveStatus == .saved)
            }
            .controlSize(.large)

            if let saveError {
                Text(saveError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button("Try a Different Speed") {
                renderer.cancel()
            }
            .font(.subheadline)
        }
        .padding()
    }

    private var saveTitle: String {
        switch saveStatus {
        case .idle, .failed: return "Save to Photos"
        case .saving: return "Saving"
        case .saved: return "Saved"
        }
    }

    private var saveError: String? {
        if case .failed(let message) = saveStatus { return message }
        return nil
    }

    private func saveToPhotos(_ url: URL) async {
        saveStatus = .saving
        let access = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard access == .authorized || access == .limited else {
            saveStatus = .failed("Same Spot isn't allowed to add to Photos. You can change that in Settings.")
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
            saveStatus = .saved
        } catch {
            saveStatus = .failed(error.localizedDescription)
        }
    }

    private static func lengthText(_ seconds: Double) -> String {
        if seconds < 60 {
            return String(format: "%.1f seconds", seconds)
        }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
