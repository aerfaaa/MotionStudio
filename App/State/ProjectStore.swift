import Foundation
import MotionCore
import Observation

/// One project folder on disk.
struct ProjectEntry: Identifiable, Hashable {
    let url: URL
    let name: String
    let modified: Date
    var id: URL { url }
}

/// What the New Project screen collects.
struct NewProjectSettings {
    var name = "Untitled"
    var resolution = ResolutionPreset.all[0]
    var frameRate = FrameRateOption.all.first(where: { $0.rate == .fps30 }) ?? FrameRateOption.all[0]
    var durationSeconds = 5.0
}

/// Finds, creates and deletes project folders in the app's Documents/Projects folder.
/// That folder is visible in the Files app (see UIFileSharingEnabled in project.yml).
@Observable
final class ProjectStore {
    private(set) var entries: [ProjectEntry] = []
    let rootURL: URL

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        rootURL = documents.appendingPathComponent("Projects", isDirectory: true)
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        reload()
    }

    func reload() {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: rootURL, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        entries = urls
            .filter { $0.pathExtension == "motionproj" }
            .map { url in
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? Date.distantPast
                return ProjectEntry(url: url, name: url.deletingPathExtension().lastPathComponent, modified: modified)
            }
            .sorted { $0.modified > $1.modified }
    }

    func create(_ settings: NewProjectSettings) throws -> (entry: ProjectEntry, project: Project) {
        let folder = uniqueFolderURL(for: settings.name)
        let displayName = folder.deletingPathExtension().lastPathComponent
        let project = Project.makeNew(name: displayName,
                                      width: settings.resolution.width,
                                      height: settings.resolution.height,
                                      frameRate: settings.frameRate.rate,
                                      durationSeconds: settings.durationSeconds)
        try ProjectFile.save(project, toFolder: folder)
        reload()
        return (ProjectEntry(url: folder, name: displayName, modified: Date()), project)
    }

    /// Used by the `-demo` launch option (for automatic screenshots). Only ever replaces its own folder.
    func createDemo() throws -> (entry: ProjectEntry, project: Project) {
        let folder = rootURL.appendingPathComponent("Sample Demo.motionproj", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        var project = SampleProjects.demo()
        project.name = "Sample Demo"
        try ProjectFile.save(project, toFolder: folder)
        reload()
        return (ProjectEntry(url: folder, name: "Sample Demo", modified: Date()), project)
    }

    func load(_ entry: ProjectEntry) throws -> Project {
        try ProjectFile.load(fromFolder: entry.url)
    }

    func delete(_ entry: ProjectEntry) {
        try? FileManager.default.removeItem(at: entry.url)
        reload()
    }

    // MARK: Private

    private func uniqueFolderURL(for name: String) -> URL {
        let cleaned = ProjectStore.sanitised(name)
        var candidate = rootURL.appendingPathComponent(cleaned + ".motionproj", isDirectory: true)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = rootURL.appendingPathComponent("\(cleaned) \(counter).motionproj", isDirectory: true)
            counter += 1
        }
        return candidate
    }

    static func sanitised(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:?*\"<>|")
        let cleaned = name.components(separatedBy: forbidden).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty || cleaned.hasPrefix(".") { return "Untitled" }
        return String(cleaned.prefix(60))
    }
}
