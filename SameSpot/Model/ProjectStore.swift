import Foundation

enum StoreError: LocalizedError {
    case missingProject

    var errorDescription: String? {
        "That project isn't here anymore."
    }
}

/// Changes whenever reminders need rescheduling.
struct ReminderSignature: Equatable {
    let id: UUID
    let name: String
    let hasTemplate: Bool
    let reminders: ReminderSchedule
}

/// Everything lives in Documents/Projects: one projects.json index, plus a folder of photos per project.
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [Project] = []

    let rootURL: URL
    private let fileManager = FileManager.default
    private var indexURL: URL { rootURL.appendingPathComponent("projects.json") }

    init(rootURL: URL? = nil) {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.rootURL = rootURL ?? documents.appendingPathComponent("Projects", isDirectory: true)
        try? fileManager.createDirectory(at: self.rootURL, withIntermediateDirectories: true)
        load()
        #if DEBUG
        seedDemoProjectIfRequested()
        #endif
    }

    // MARK: Lookup

    func project(_ id: UUID?) -> Project? {
        guard let id else { return nil }
        return projects.first { $0.id == id }
    }

    func folder(for projectID: UUID) -> URL {
        rootURL.appendingPathComponent(projectID.uuidString, isDirectory: true)
    }

    func templateURL(for project: Project) -> URL? {
        project.templateFile.map { folder(for: project.id).appendingPathComponent($0) }
    }

    func url(for frame: Frame, in project: Project) -> URL {
        folder(for: project.id).appendingPathComponent(frame.file)
    }

    /// The photo the camera ghosts over the live view.
    func overlayURL(for project: Project) -> URL? {
        if project.overlaySource == .latest, let last = project.frames.last {
            return url(for: last, in: project)
        }
        return templateURL(for: project)
    }

    var reminderSignature: [ReminderSignature] {
        projects.map {
            ReminderSignature(id: $0.id, name: $0.name, hasTemplate: $0.hasTemplate, reminders: $0.reminders)
        }
    }

    // MARK: Changes

    @discardableResult
    func createProject(name: String, reminders: ReminderSchedule) -> Project {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var project = Project(name: trimmed.isEmpty ? "Untitled" : trimmed)
        project.reminders = reminders
        try? fileManager.createDirectory(at: folder(for: project.id), withIntermediateDirectories: true)
        projects.insert(project, at: 0)
        save()
        return project
    }

    func rename(_ projectID: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        modify(projectID) { $0.name = trimmed }
    }

    func setReminders(_ reminders: ReminderSchedule, for projectID: UUID) {
        modify(projectID) { $0.reminders = reminders }
    }

    func setOverlayOpacity(_ opacity: Double, for projectID: UUID) {
        modify(projectID) { $0.overlayOpacity = opacity }
    }

    func setOverlaySource(_ source: OverlaySource, for projectID: UUID) {
        modify(projectID) { $0.overlaySource = source }
    }

    /// Saves a new original. The first one also becomes day one of the timelapse and fixes the
    /// project's orientation. A retake only swaps the guide; the frames already taken stay put.
    func setTemplate(_ photo: CapturedPhoto, for projectID: UUID) throws {
        guard let index = index(of: projectID) else { throw StoreError.missingProject }
        let file = "original-\(UUID().uuidString).\(photo.fileExtension)"
        try write(photo.data, named: file, in: projectID)

        let oldFile = projects[index].templateFile
        if oldFile == nil {
            projects[index].captureAngle = photo.angle
        }
        projects[index].templateFile = file
        projects[index].templateDate = photo.date

        if projects[index].frames.isEmpty {
            let frameID = UUID()
            let frame = Frame(id: frameID, date: photo.date, file: "\(frameID.uuidString).\(photo.fileExtension)")
            do {
                try write(photo.data, named: frame.file, in: projectID)
                projects[index].frames.append(frame)
            } catch {
                // The original is saved either way. Missing day one isn't worth failing over.
            }
        }
        save()

        if let oldFile {
            try? fileManager.removeItem(at: folder(for: projectID).appendingPathComponent(oldFile))
        }
    }

    @discardableResult
    func addFrame(_ photo: CapturedPhoto, to projectID: UUID) throws -> Frame {
        guard let index = index(of: projectID) else { throw StoreError.missingProject }
        let frameID = UUID()
        let frame = Frame(id: frameID, date: photo.date, file: "\(frameID.uuidString).\(photo.fileExtension)")
        try write(photo.data, named: frame.file, in: projectID)
        projects[index].frames.append(frame)
        projects[index].frames.sort { $0.date < $1.date }
        save()
        return frame
    }

    func deleteFrame(_ frameID: UUID, in projectID: UUID) {
        guard let index = index(of: projectID),
              let frameIndex = projects[index].frames.firstIndex(where: { $0.id == frameID }) else { return }
        let frame = projects[index].frames.remove(at: frameIndex)
        save()
        try? fileManager.removeItem(at: folder(for: projectID).appendingPathComponent(frame.file))
    }

    func deleteProject(_ projectID: UUID) {
        projects.removeAll { $0.id == projectID }
        save()
        try? fileManager.removeItem(at: folder(for: projectID))
    }

    // MARK: Disk

    /// Bytes on disk under a folder. Walks every file, so call it off the main thread.
    static func diskUsage(at folder: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: Array(keys)) else {
            return 0
        }
        var total: Int64 = 0
        for case let file as URL in files {
            guard let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    private func index(of projectID: UUID) -> Int? {
        projects.firstIndex { $0.id == projectID }
    }

    private func modify(_ projectID: UUID, _ change: (inout Project) -> Void) {
        guard let index = index(of: projectID) else { return }
        var project = projects[index]
        change(&project)
        guard project != projects[index] else { return }
        projects[index] = project
        save()
    }

    private func write(_ data: Data, named name: String, in projectID: UUID) throws {
        let folder = folder(for: projectID)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: folder.appendingPathComponent(name), options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        do {
            projects = try JSONDecoder().decode([Project].self, from: data)
        } catch {
            // Move the unreadable index aside so the next save can't overwrite someone's projects.
            let backup = rootURL.appendingPathComponent("projects-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? fileManager.moveItem(at: indexURL, to: backup)
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(projects)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            assertionFailure("Couldn't save projects: \(error)")
        }
    }
}
