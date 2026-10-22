import SwiftUI

/// The camera, with the project's guide photo ghosted over the live view.
struct CaptureView: View {
    let project: Project
    @Binding var showingNewProject: Bool

    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var camera: CameraModel
    @Environment(\.openURL) private var openURL

    @AppStorage("showGrid") private var showGrid = true
    @State private var opacity: Double = 0.35
    @State private var overlayImage: UIImage?
    // Gesture state resets itself if the hold is interrupted (a call, Control Center), so the
    // guide can't get stuck at full strength.
    @GestureState private var isPeeking = false
    @State private var review: Review?
    @State private var flashOpacity: Double = 0
    @State private var toast: Toast?
    @State private var shutterCount = 0
    @State private var errorMessage: String?
    @State private var viewerItem: ViewerItem?

    /// A just-taken original, waiting for Use Photo or Retake.
    private struct Review {
        let projectID: UUID
        let photo: CapturedPhoto
        let image: UIImage?
    }

    private struct Toast: Equatable {
        let id = UUID()
        let text: String
    }

    private enum Mode: Equatable {
        case original
        case retake
        case frame
    }

    private var mode: Mode {
        if !project.hasTemplate { return .original }
        if router.retakeProjectID == project.id { return .retake }
        return .frame
    }

    private var overlayURL: URL? {
        switch mode {
        case .original: return nil
        case .retake: return store.templateURL(for: project)
        case .frame: return store.overlayURL(for: project)
        }
    }

    /// Clockwise turn that puts a stored, upright photo back the way the portrait live view shows it.
    private var overlayRotation: Double { 90 - project.captureAngle }

    private var cameraReady: Bool {
        CameraModel.isSimulator || camera.status == .running
    }

    private var canShoot: Bool {
        review == nil && cameraReady && !camera.isCapturing
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                viewfinder
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                controls
                    .frame(height: 132)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
            }
        }
        .environment(\.colorScheme, .dark)
        .navigationTitle(project.name)
        .toolbar { toolbarContent }
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
        .onChange(of: project.id, initial: true) {
            opacity = project.overlayOpacity
            review = nil
            // Never draw the last project's guide over this one while its own decodes.
            overlayImage = overlayURL.flatMap { ImageLoader.shared.cachedImage(at: $0, maxPixel: 1600) }
        }
        .onChange(of: router.reminderTapCount) {
            viewerItem = nil
        }
        // A retake that ends some other way (tab switch, reminder tap) takes its pending review with it,
        // or Retake on that review would drop into normal mode and save the next shot as a frame.
        .onChange(of: router.retakeProjectID) { oldValue, newValue in
            if oldValue == project.id, newValue != project.id {
                review = nil
            }
        }
        .task(id: overlayURL) {
            guard let url = overlayURL else {
                overlayImage = nil
                return
            }
            let image = await ImageLoader.shared.image(at: url, maxPixel: 1600)
            // A newer guide was asked for while this one decoded.
            guard !Task.isCancelled else { return }
            overlayImage = image
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: shutterCount)
        .alert("Couldn't Take Photo", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .fullScreenCover(item: $viewerItem) { item in
            PhotoViewer(projectID: item.projectID, startFrameID: item.frameID)
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Menu {
                Picker("Project", selection: projectSelection) {
                    ForEach(store.projects) { item in
                        Text(item.name).tag(item.id)
                    }
                }
                Divider()
                Button {
                    showingNewProject = true
                } label: {
                    Label("New Project", systemImage: "plus")
                }
            } label: {
                HStack(spacing: 5) {
                    Text(project.name)
                        .font(.headline)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.white.opacity(0.7))
                }
                .foregroundStyle(Color.white)
            }
            .accessibilityLabel("Project, \(project.name)")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showGrid.toggle()
            } label: {
                Image(systemName: "squareshape.split.3x3")
                    .foregroundStyle(showGrid ? Color.yellow : Color.white)
            }
            .accessibilityLabel(showGrid ? "Hide Grid" : "Show Grid")
        }
    }

    private var projectSelection: Binding<UUID> {
        Binding {
            project.id
        } set: { id in
            // Re-picking the checked project is how people close the menu. It shouldn't cancel a retake.
            if id != project.id {
                router.openCamera(for: id)
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding {
            errorMessage != nil
        } set: { isShowing in
            if !isShowing { errorMessage = nil }
        }
    }

    // MARK: Viewfinder

    private var viewfinder: some View {
        ZStack {
            livePreview

            if let review {
                if let image = review.image {
                    RotatedImage(image: image, rotation: 90 - review.photo.angle)
                }
            } else {
                if let overlayImage {
                    RotatedImage(image: overlayImage, rotation: overlayRotation)
                        .opacity(isPeeking ? 1 : opacity)
                        .allowsHitTesting(false)
                }
                if showGrid {
                    GridLines()
                }
            }

            Color.black
                .opacity(flashOpacity)
                .allowsHitTesting(false)

            VStack {
                hint
                Spacer()
                if let toast {
                    Text(toast.text)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 14)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .clipped()
    }

    @ViewBuilder
    private var livePreview: some View {
        if CameraModel.isSimulator {
            RotatedImage(image: SimulatedCamera.previewImage, rotation: 0)
        } else {
            switch camera.status {
            case .unauthorized:
                cameraMessage(
                    title: "Camera access is off",
                    detail: "Same Spot needs the camera to take your photos. You can turn it on in Settings.",
                    showSettings: true
                )
            case .unavailable:
                cameraMessage(
                    title: "No camera",
                    detail: "Same Spot couldn't find a back camera it can use on this device.",
                    showSettings: false
                )
            case .idle, .running:
                CameraPreview(session: camera.session)
            }
        }
    }

    private func cameraMessage(title: String, detail: String, showSettings: Bool) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "camera.fill")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if showSettings {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 6)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.08))
    }

    @ViewBuilder
    private var hint: some View {
        if review != nil {
            HintPill(text: "Use this as the original? Every photo after this lines up with it.")
        } else {
            switch mode {
            case .original:
                HintPill(text: "Find your spot and take the original. It becomes the guide for every photo after it.")
            case .retake:
                HintPill(text: "Retaking the original. The old one is ghosted in so you can match it.")
            case .frame:
                EmptyView()
            }
        }
    }

    // MARK: Controls

    @ViewBuilder
    private var controls: some View {
        if let review {
            HStack {
                Button("Retake") {
                    self.review = nil
                }
                Spacer()
                Button("Use Photo") {
                    useOriginal(review)
                }
                .fontWeight(.semibold)
            }
            .font(.title3)
            .foregroundStyle(Color.white)
        } else {
            VStack(spacing: 18) {
                opacityRow
                HStack {
                    leftButton
                        .frame(width: 64, height: 64)
                    Spacer()
                    ShutterButton(isEnabled: canShoot, isDimmed: !cameraReady) {
                        shoot()
                    }
                    Spacer()
                    peekButton
                        .frame(width: 64, height: 64)
                }
            }
        }
    }

    private var opacityRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "circle.dotted")
                .accessibilityHidden(true)
            Slider(value: $opacity, in: 0...1, onEditingChanged: { editing in
                if !editing {
                    store.setOverlayOpacity(opacity, for: project.id)
                }
            })
            .tint(Color.yellow)
            .accessibilityLabel("Guide strength")
            Image(systemName: "circle.fill")
                .accessibilityHidden(true)
            if mode == .frame {
                overlaySourceMenu
            }
        }
        .font(.footnote)
        .foregroundStyle(Color.white.opacity(0.8))
        .opacity(mode == .original ? 0 : 1)
        .disabled(mode == .original)
    }

    private var overlaySourceMenu: some View {
        Menu {
            Picker("Line Up With", selection: overlaySourceSelection) {
                Label("Original", systemImage: "star").tag(OverlaySource.original)
                Label("Last Photo", systemImage: "clock.arrow.circlepath").tag(OverlaySource.latest)
            }
        } label: {
            Text(project.overlaySource == .original ? "Original" : "Last")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.18), in: Capsule())
        }
        .accessibilityLabel("Line up with")
    }

    private var overlaySourceSelection: Binding<OverlaySource> {
        Binding {
            project.overlaySource
        } set: { source in
            store.setOverlaySource(source, for: project.id)
        }
    }

    @ViewBuilder
    private var leftButton: some View {
        switch mode {
        case .frame:
            if let last = project.frames.last {
                Button {
                    viewerItem = ViewerItem(projectID: project.id, frameID: last.id)
                } label: {
                    ThumbnailView(url: store.url(for: last, in: project), maxPixel: 200)
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.85), lineWidth: 1.5)
                        )
                }
                .accessibilityLabel("Last photo")
            }
        case .retake:
            Button("Cancel") {
                router.retakeProjectID = nil
            }
            .foregroundStyle(Color.white)
        case .original:
            EmptyView()
        }
    }

    @ViewBuilder
    private var peekButton: some View {
        if mode != .original, overlayImage != nil {
            Image(systemName: isPeeking ? "eye.fill" : "eye")
                .font(.title3)
                .foregroundStyle(isPeeking ? Color.yellow : Color.white)
                .frame(width: 52, height: 52)
                .background(Color.white.opacity(0.18), in: Circle())
                .contentShape(Circle())
                // Hold to see the guide at full strength, let go to go back.
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .updating($isPeeking) { _, peeking, _ in peeking = true }
                )
                .accessibilityLabel("Hold to compare")
                .accessibilityAddTraits(.isButton)
        }
    }

    // MARK: Actions

    private func shoot() {
        let currentMode = mode
        let projectID = project.id
        // Once a project has an original, every photo uses its rotation.
        let lockedAngle: Double? = project.hasTemplate ? project.captureAngle : nil

        withAnimation(.easeIn(duration: 0.05)) {
            flashOpacity = 0.85
        } completion: {
            withAnimation(.easeOut(duration: 0.25)) {
                flashOpacity = 0
            }
        }

        camera.capture(lockedAngle: lockedAngle) { result in
            switch result {
            case .failure(let error):
                errorMessage = error.localizedDescription
            case .success(let photo):
                shutterCount += 1
                if currentMode == .frame {
                    saveFrame(photo, to: projectID)
                } else {
                    review = Review(
                        projectID: projectID,
                        photo: photo,
                        image: ImageLoader.image(from: photo.data, maxPixel: 1600)
                    )
                }
            }
        }
    }

    private func saveFrame(_ photo: CapturedPhoto, to projectID: UUID) {
        do {
            try store.addFrame(photo, to: projectID)
            let count = store.project(projectID)?.frames.count ?? 0
            showToast(count == 1 ? "Saved. 1 photo so far." : "Saved. \(count) photos so far.")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func useOriginal(_ review: Review) {
        let isFirst = store.project(review.projectID)?.hasTemplate == false
        do {
            try store.setTemplate(review.photo, for: review.projectID)
            if router.retakeProjectID == review.projectID {
                router.retakeProjectID = nil
            }
            self.review = nil
            showToast(isFirst ? "Original saved. It's photo 1 of the timelapse." : "New original saved.")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func showToast(_ text: String) {
        let next = Toast(text: text)
        withAnimation(.snappy) { toast = next }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            if toast == next {
                withAnimation(.snappy) { toast = nil }
            }
        }
    }
}

// MARK: - Pieces

/// Draws an upright photo turned by a multiple of 90 degrees, filling its frame.
struct RotatedImage: View {
    let image: UIImage
    let rotation: Double

    var body: some View {
        GeometryReader { geo in
            let quarterTurn = Int(rotation.rounded()) % 180 != 0
            let width = quarterTurn ? geo.size.height : geo.size.width
            let height = quarterTurn ? geo.size.width : geo.size.height
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: width, height: height)
                .clipped()
                .rotationEffect(.degrees(rotation))
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

struct GridLines: View {
    var body: some View {
        GeometryReader { geo in
            Path { path in
                let w = geo.size.width
                let h = geo.size.height
                for i in 1...2 {
                    let x = w * CGFloat(i) / 3
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: h))
                    let y = h * CGFloat(i) / 3
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: w, y: y))
                }
            }
            .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct HintPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote.weight(.medium))
            .multilineTextAlignment(.center)
            .foregroundStyle(Color.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(12)
    }
}

struct ShutterButton: View {
    var isEnabled: Bool
    var isDimmed: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(Color.white, lineWidth: 4)
                Circle()
                    .fill(Color.white)
                    .padding(9)
            }
            .frame(width: 76, height: 76)
            .contentShape(Circle())
        }
        .buttonStyle(ShutterButtonStyle())
        .disabled(!isEnabled)
        .opacity(isDimmed ? 0.4 : 1)
        .accessibilityLabel("Take Photo")
    }
}

private struct ShutterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
