import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers
import MotionCore

struct ImportedMediaFile {
    let asset: Asset
    let duration: Double
    let pixelSize: Vec2?
}

enum MediaFileImportError: LocalizedError {
    case unsupported
    case unreadable
    case copyFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupported: return "This file type is not supported. Choose an image, video, audio file, or font."
        case .unreadable: return "The selected media could not be read. It may be damaged or unsupported."
        case .copyFailed(let detail): return "The file could not be copied into the project. \(detail)"
        }
    }
}

enum MediaFileImporter {
    static func importFile(from sourceURL: URL, projectFolder: URL) throws -> ImportedMediaFile {
        let hasScope = sourceURL.startAccessingSecurityScopedResource()
        defer { if hasScope { sourceURL.stopAccessingSecurityScopedResource() } }

        let resourceType = try? sourceURL.resourceValues(forKeys: [.contentTypeKey]).contentType
        let extensionType = UTType(filenameExtension: sourceURL.pathExtension)
        // Some document providers report only the generic public.data type. Prefer the extension-derived
        // type in that case so MP4/MOV/M4A files are not incorrectly rejected on iPad.
        func isRecognised(_ candidate: UTType?) -> Bool {
            guard let candidate else { return false }
            if candidate.conforms(to: .image) || candidate.conforms(to: .movie)
                || candidate.conforms(to: .video) || candidate.conforms(to: .audio) { return true }
            let ext = candidate.preferredFilenameExtension?.lowercased() ?? sourceURL.pathExtension.lowercased()
            return ext == "ttf" || ext == "otf"
        }
        let type: UTType?
        if isRecognised(resourceType) {
            type = resourceType
        } else if isRecognised(extensionType) {
            type = extensionType
        } else {
            type = resourceType ?? extensionType
        }
        guard let type else { throw MediaFileImportError.unsupported }

        if type.conforms(to: .image) {
            let asset = try ImageImporter.importFile(from: sourceURL, projectFolder: projectFolder)
            return ImportedMediaFile(asset: asset, duration: 0, pixelSize: asset.pixelSize)
        }

        let kind: AssetKind
        if type.conforms(to: .movie) || type.conforms(to: .video) {
            kind = .video
        } else if type.conforms(to: .audio) {
            kind = .audio
        } else if type.preferredFilenameExtension?.lowercased() == "ttf"
                    || type.preferredFilenameExtension?.lowercased() == "otf"
                    || sourceURL.pathExtension.lowercased() == "ttf"
                    || sourceURL.pathExtension.lowercased() == "otf" {
            kind = .font
        } else {
            throw MediaFileImportError.unsupported
        }

        let relativePath: String
        do {
            relativePath = try ProjectMedia.importFile(at: sourceURL, intoProjectFolder: projectFolder)
        } catch {
            throw MediaFileImportError.copyFailed(error.localizedDescription)
        }
        let asset = Asset(kind: kind, displayName: sourceURL.lastPathComponent, relativePath: relativePath)

        if kind == .video || kind == .audio {
            let storedURL = ProjectMedia.fileURL(for: asset, inProjectFolder: projectFolder)!
            let media = AVURLAsset(url: storedURL)
            let seconds = media.duration.seconds
            guard seconds.isFinite, seconds > 0 else {
                ProjectMedia.removeFile(relativePath: relativePath, inProjectFolder: projectFolder)
                throw MediaFileImportError.unreadable
            }
            var pixelSize: Vec2?
            if kind == .video, let track = media.tracks(withMediaType: .video).first {
                let transformed = track.naturalSize.applying(track.preferredTransform)
                let width = abs(Double(transformed.width))
                let height = abs(Double(transformed.height))
                if width > 0, height > 0 { pixelSize = Vec2(x: width, y: height) }
            }
            return ImportedMediaFile(asset: asset, duration: seconds, pixelSize: pixelSize)
        }
        return ImportedMediaFile(asset: asset, duration: 0, pixelSize: nil)
    }
}

enum AudioExtractor {
    static func extract(from videoURL: URL, projectFolder: URL) async throws -> (asset: Asset, duration: Double) {
        let hasScope = videoURL.startAccessingSecurityScopedResource()
        defer { if hasScope { videoURL.stopAccessingSecurityScopedResource() } }
        let asset = AVURLAsset(url: videoURL)
        guard !asset.tracks(withMediaType: .audio).isEmpty else {
            throw NSError(domain: "MotionStudio.AudioExtraction", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "This video does not contain an audio track."])
        }
        let duration = asset.duration.seconds
        guard duration.isFinite, duration > 0 else {
            throw NSError(domain: "MotionStudio.AudioExtraction", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "The video duration could not be read."])
        }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MotionStudio-Audio-\(UUID().uuidString).m4a")
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw NSError(domain: "MotionStudio.AudioExtraction", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Audio export is not available for this video."])
        }
        exporter.outputURL = tempURL
        exporter.outputFileType = .m4a
        exporter.shouldOptimizeForNetworkUse = false
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            exporter.exportAsynchronously {
                switch exporter.status {
                case .completed: continuation.resume()
                case .cancelled:
                    continuation.resume(throwing: CancellationError())
                case .failed:
                    continuation.resume(throwing: exporter.error ?? NSError(domain: "MotionStudio.AudioExtraction", code: 4))
                default:
                    continuation.resume(throwing: NSError(domain: "MotionStudio.AudioExtraction", code: 5,
                                                           userInfo: [NSLocalizedDescriptionKey: "Audio extraction ended unexpectedly."]))
                }
            }
        }
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let relative = try ProjectMedia.importFile(at: tempURL, intoProjectFolder: projectFolder)
        let outputAsset = Asset(kind: .audio,
                                displayName: "\((videoURL.deletingPathExtension().lastPathComponent)) Audio.m4a",
                                relativePath: relative)
        return (outputAsset, duration)
    }
}
