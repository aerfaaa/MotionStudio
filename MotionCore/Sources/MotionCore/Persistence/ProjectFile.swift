import Foundation

public enum ProjectFileError: Error, Equatable, LocalizedError {
    case notFound
    /// The file was saved by a newer version of the app.
    case newerThanApp(found: Int, supported: Int)
    case corrupt(String)

    public var errorDescription: String? {
        switch self {
        case .notFound:
            return "The project file could not be found."
        case .newerThanApp(let found, let supported):
            return "This project was saved by a newer version of the app (format \(found); this app understands up to \(supported)). Update the app to open it."
        case .corrupt(let detail):
            return "The project file is damaged or unreadable. \(detail)"
        }
    }
}

/// Saving and opening projects.
///
/// A project is a FOLDER, for example `Holiday.motionproj/`, containing `project.json`
/// and a `media/` folder for imported files. JSON is written with sorted keys so the
/// output is stable and easy to compare in Git.
public enum ProjectFile {
    public static let fileName = "project.json"
    public static let mediaFolderName = "media"

    public static func encode(_ project: Project) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(project)
    }

    public static func decode(_ data: Data) throws -> Project {
        let decoder = JSONDecoder()

        // Read only the version first, so a newer file gives a clear message instead of a confusing error.
        let probe: VersionProbe
        do {
            probe = try decoder.decode(VersionProbe.self, from: data)
        } catch {
            throw ProjectFileError.corrupt("No format version was found.")
        }
        guard probe.schemaVersion >= 1 else {
            throw ProjectFileError.corrupt("The format version is invalid.")
        }
        guard probe.schemaVersion <= Project.currentSchemaVersion else {
            throw ProjectFileError.newerThanApp(found: probe.schemaVersion, supported: Project.currentSchemaVersion)
        }

        // Future: when the format changes, upgrade older versions here before decoding.

        let project: Project
        do {
            project = try decoder.decode(Project.self, from: data)
        } catch {
            throw ProjectFileError.corrupt(String(describing: error))
        }
        try validate(project)
        return project
    }

    public static func save(_ project: Project, toFolder folder: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: folder.appendingPathComponent(mediaFolderName, isDirectory: true),
                                        withIntermediateDirectories: true)
        let data = try encode(project)
        // .atomic writes to a temporary file first, so a crash mid-save cannot damage the old file.
        try data.write(to: folder.appendingPathComponent(fileName), options: .atomic)
    }

    public static func load(fromFolder folder: URL) throws -> Project {
        let file = folder.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw ProjectFileError.notFound
        }
        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch {
            throw ProjectFileError.corrupt("The file could not be read.")
        }
        return try decode(data)
    }

    // MARK: Private

    private struct VersionProbe: Decodable {
        let schemaVersion: Int
    }

    /// Rejects files that would crash or misbehave later (empty project, zero-size composition...).
    private static func validate(_ project: Project) throws {
        guard !project.compositions.isEmpty else {
            throw ProjectFileError.corrupt("The project has no composition.")
        }
        guard project.compositions.contains(where: { $0.id == project.rootCompositionID }) else {
            throw ProjectFileError.corrupt("The main composition is missing.")
        }
        for composition in project.compositions {
            guard composition.width > 0, composition.height > 0,
                  composition.width <= 16384, composition.height <= 16384 else {
                throw ProjectFileError.corrupt("A composition has an invalid size.")
            }
            guard composition.duration.ticks > 0, composition.duration <= Time.maximumDuration else {
                throw ProjectFileError.corrupt("A composition has an invalid length.")
            }
        }
    }
}
