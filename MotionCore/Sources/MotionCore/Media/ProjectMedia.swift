import Foundation

public enum MediaError: Error, Equatable, LocalizedError {
    case copyFailed(String)
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .copyFailed(let detail): return "The file could not be copied into the project. \(detail)"
        case .writeFailed(let detail): return "The file could not be saved into the project. \(detail)"
        }
    }
}

/// Keeps imported files inside the project folder, so a project keeps working after the app restarts,
/// is duplicated, or the original file (or a temporary picker file) disappears.
///
/// Layout: `MyProject.motionproj/media/<8 characters>-<name>.<extension>`. The project file stores only
/// that relative path. Paths that try to escape the media folder are refused.
public enum ProjectMedia {
    public static let folderName = "media"

    /// A file name that is safe on every file system.
    public static func safeFileName(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:?*\"<>|\n\r\t")
        let cleaned = name.components(separatedBy: forbidden).joined(separator: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespacesAndNewlines))
        var result = cleaned
        // ".." could be read as "go up a folder", so it never survives in a file name.
        while result.contains("..") { result = result.replacingOccurrences(of: "..", with: "-") }
        if result.isEmpty { return "media" }
        return String(result.prefix(60))
    }

    private static func safeExtension(_ text: String) -> String {
        let letters = text.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        return letters.isEmpty ? "dat" : String(letters.prefix(8))
    }

    private static func destination(baseName: String, fileExtension: String, folder: URL) throws -> (url: URL, relativePath: String) {
        let mediaFolder = folder.appendingPathComponent(folderName, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: mediaFolder, withIntermediateDirectories: true)
        } catch {
            throw MediaError.writeFailed(error.localizedDescription)
        }
        let prefix = String(UUID().uuidString.prefix(8))
        let fileName = "\(prefix)-\(safeFileName(baseName)).\(safeExtension(fileExtension))"
        return (mediaFolder.appendingPathComponent(fileName), "\(folderName)/\(fileName)")
    }

    /// Copies a file into the project's media folder and returns its relative path.
    public static func importFile(at source: URL, intoProjectFolder folder: URL) throws -> String {
        let base = source.deletingPathExtension().lastPathComponent
        let target = try destination(baseName: base, fileExtension: source.pathExtension, folder: folder)
        do {
            try FileManager.default.copyItem(at: source, to: target.url)
        } catch {
            throw MediaError.copyFailed(error.localizedDescription)
        }
        return target.relativePath
    }

    /// Writes data (for example a photo from the Photos library) into the media folder and returns its relative path.
    public static func importData(_ data: Data, fileExtension: String, baseName: String,
                                  intoProjectFolder folder: URL) throws -> String {
        let target = try destination(baseName: baseName, fileExtension: fileExtension, folder: folder)
        do {
            try data.write(to: target.url, options: .atomic)
        } catch {
            throw MediaError.writeFailed(error.localizedDescription)
        }
        return target.relativePath
    }

    /// The file for an asset, or nil if its stored path is not a plain `media/<file>` path.
    public static func fileURL(for asset: Asset, inProjectFolder folder: URL) -> URL? {
        let parts = asset.relativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, parts[0] == folderName,
              !parts[1].isEmpty, parts[1] != ".", parts[1] != "..",
              !parts[1].contains("\\") else { return nil }
        return folder.appendingPathComponent(folderName, isDirectory: true).appendingPathComponent(parts[1])
    }

    public static func fileExists(for asset: Asset, inProjectFolder folder: URL) -> Bool {
        guard let url = fileURL(for: asset, inProjectFolder: folder) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Assets whose files are not in the project folder.
    public static func missingAssets(in project: Project, folder: URL) -> [Asset] {
        project.assets.filter { !fileExists(for: $0, inProjectFolder: folder) }
    }

    public static func removeFile(relativePath: String, inProjectFolder folder: URL) {
        let asset = Asset(kind: .image, displayName: "", relativePath: relativePath)
        if let url = fileURL(for: asset, inProjectFolder: folder) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

/// Makes a layer for an imported image.
public enum ImageLayerFactory {

    /// The size of an image layer: the whole picture, shrunk or enlarged to fit inside `fraction` of the
    /// composition, keeping its proportions.
    public static func fittedSize(pixelSize: Vec2, in composition: Composition, fraction: Double = 0.8) -> Vec2? {
        guard pixelSize.x > 0, pixelSize.y > 0, pixelSize.x.isFinite, pixelSize.y.isFinite else { return nil }
        let scale = min(Double(composition.width) * fraction / pixelSize.x,
                        Double(composition.height) * fraction / pixelSize.y)
        return Vec2(x: pixelSize.x * scale, y: pixelSize.y * scale)
    }

    /// A layer centred in the composition that lasts for the whole composition.
    public static func makeLayer(for asset: Asset, in composition: Composition) -> Layer? {
        guard asset.kind == .image, let pixelSize = asset.pixelSize,
              let size = fittedSize(pixelSize: pixelSize, in: composition) else { return nil }
        let name = (asset.displayName as NSString).deletingPathExtension
        return Layer(name: name.isEmpty ? "Image" : name,
                     kind: .image(assetID: asset.id),
                     size: size,
                     fill: RGBA(r: 0.62, g: 0.64, b: 0.70),
                     inPoint: .zero,
                     outPoint: composition.duration,
                     position: composition.center)
    }
}

/// Adds an image to the project and a layer that shows it, as one undoable step.
public struct AddMediaLayer: Command {
    public let compositionID: UUID
    public let asset: Asset
    public let layer: Layer
    public let index: Int

    public init(compositionID: UUID, asset: Asset, layer: Layer, index: Int = 0) {
        self.compositionID = compositionID
        self.asset = asset
        self.layer = layer
        self.index = index
    }

    public var name: String { "Import Image" }

    public func apply(to project: inout Project) throws {
        guard asset.kind == .image, case .image(let layerAssetID) = layer.kind, layerAssetID == asset.id else {
            throw EditError.invalidAsset
        }
        if !project.assets.contains(where: { $0.id == asset.id }) {
            project.assets.append(asset)
        }
        try AddLayer(compositionID: compositionID, layer: layer, index: index).apply(to: &project)
    }
}
