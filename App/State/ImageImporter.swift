import Foundation
import ImageIO
import UniformTypeIdentifiers
import MotionCore

enum ImageImportError: LocalizedError {
    case notAnImage
    case unreadable
    case tooLarge(width: Int, height: Int)
    case storage(String)

    var errorDescription: String? {
        switch self {
        case .notAnImage:
            return "That file is not a picture this device can read."
        case .unreadable:
            return "The picture could not be read. It may be damaged or in an unsupported format."
        case .tooLarge(let width, let height):
            return "That picture is too large (\(width) by \(height) pixels). The limit is \(ImageImporter.maximumSide) pixels on a side."
        case .storage(let detail):
            return "The picture could not be saved into the project. \(detail)"
        }
    }
}

/// Checks a picture and copies it into the project's media folder.
/// Only a small version is ever decoded here, so large photos do not use much memory.
enum ImageImporter {
    static let maximumSide = 16384
    static let maximumPixels = 150_000_000

    /// Size in pixels after the photo's rotation is applied. Throws if the file is not a readable picture.
    static func inspect(_ url: URL) throws -> (width: Int, height: Int) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0 else {
            throw ImageImportError.notAnImage
        }
        guard let typeName = CGImageSourceGetType(source), let type = UTType(typeName as String),
              type.conforms(to: .image) else {
            throw ImageImportError.notAnImage
        }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              var width = properties[kCGImagePropertyPixelWidth] as? Int,
              var height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else {
            throw ImageImportError.unreadable
        }
        if let orientation = properties[kCGImagePropertyOrientation] as? Int, (5...8).contains(orientation) {
            swap(&width, &height)          // the photo was taken sideways
        }
        guard width <= maximumSide, height <= maximumSide, width * height <= maximumPixels else {
            throw ImageImportError.tooLarge(width: width, height: height)
        }
        // A small test decode catches files whose header looks fine but whose data is damaged.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 32,
        ]
        guard CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) != nil else {
            throw ImageImportError.unreadable
        }
        return (width, height)
    }

    /// Imports a file chosen in the Files app. The file is checked first, so nothing is copied if it is not a picture.
    static func importFile(from sourceURL: URL, projectFolder: URL) throws -> Asset {
        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }
        let size = try inspect(sourceURL)
        let path: String
        do {
            path = try ProjectMedia.importFile(at: sourceURL, intoProjectFolder: projectFolder)
        } catch {
            throw ImageImportError.storage(error.localizedDescription)
        }
        return Asset(kind: .image, displayName: sourceURL.lastPathComponent, relativePath: path,
                     pixelSize: Vec2(x: Double(size.width), y: Double(size.height)))
    }

    /// Imports picture data, for example from the Photos library.
    static func importData(_ data: Data, fileExtension: String, baseName: String, projectFolder: URL) throws -> Asset {
        let path: String
        do {
            path = try ProjectMedia.importData(data, fileExtension: fileExtension, baseName: baseName,
                                               intoProjectFolder: projectFolder)
        } catch {
            throw ImageImportError.storage(error.localizedDescription)
        }
        let stored = projectFolder.appendingPathComponent(path)
        do {
            let size = try inspect(stored)
            return Asset(kind: .image, displayName: stored.lastPathComponent, relativePath: path,
                         pixelSize: Vec2(x: Double(size.width), y: Double(size.height)))
        } catch {
            ProjectMedia.removeFile(relativePath: path, inProjectFolder: projectFolder)   // do not keep a bad file
            throw error
        }
    }
}
