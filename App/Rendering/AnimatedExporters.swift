import Foundation
import ImageIO
import UniformTypeIdentifiers
import UIKit
import MotionCore

/// GIF is encoded incrementally so a long animation doesn't keep every rendered frame in RAM.
enum AnimatedExporters {
    enum ExportError: LocalizedError {
        case destinationUnavailable
        case frameMissing(Int64)
        var errorDescription: String? {
            switch self {
            case .destinationUnavailable: return "The animation file could not be created."
            case .frameMissing(let frame): return "Frame \(frame) could not be encoded."
            }
        }
    }

    @MainActor
    static func exportGIF(frameCount: Int64,
                          frameRate: FrameRate,
                          frameProvider: @MainActor (Int64) async throws -> UIImage,
                          progress: @MainActor (Int64, Int64) -> Void) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MotionStudio-\(UUID().uuidString).gif")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, Int(max(1, frameCount)), nil) else {
            throw ExportError.destinationUnavailable
        }
        let fps = max(1.0, frameRate.framesPerSecond)
        let frameProperties: [CFString: Any] = [kCGImagePropertyGIFDictionary: [
            kCGImagePropertyGIFDelayTime: 1.0 / fps,
            kCGImagePropertyGIFUnclampedDelayTime: 1.0 / fps
        ]]
        let fileProperties: [CFString: Any] = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]]
        CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)
        let total = max(1, frameCount)
        for index in 0..<total {
            try Task.checkCancellation()
            let image = try await frameProvider(index)
            guard let cgImage = image.cgImage else { throw ExportError.frameMissing(index) }
            CGImageDestinationAddImage(destination, cgImage, frameProperties as CFDictionary)
            progress(index + 1, total)
        }
        guard CGImageDestinationFinalize(destination) else { throw ExportError.destinationUnavailable }
        return url
    }

    @MainActor
    static func exportImageSequence(frameCount: Int64,
                                    frameRate: FrameRate,
                                    width: Int,
                                    height: Int,
                                    frameProvider: @MainActor (Int64) async throws -> UIImage,
                                    progress: @MainActor (Int64, Int64) -> Void) async throws -> URL {
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent("MotionStudio-Sequence-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: folder) }
        let total = max(1, frameCount)
        for index in 0..<total {
            try Task.checkCancellation()
            let image = try await frameProvider(index)
            guard let data = image.pngData() else { throw ExportError.frameMissing(index) }
            let name = String(format: "frame-%06lld.png", index)
            try data.write(to: folder.appendingPathComponent(name), options: .atomic)
            progress(index + 1, total)
        }
        let manifest: [String: Any] = [
            "format": "MotionStudio PNG image sequence",
            "frameRate": frameRate.framesPerSecond,
            "frameCount": total,
            "width": width,
            "height": height,
            "filenamePattern": "frame-%06d.png",
            "audioIncluded": false
        ]
        let manifestData = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try manifestData.write(to: folder.appendingPathComponent("sequence.json"), options: .atomic)
        let archive = fm.temporaryDirectory.appendingPathComponent("MotionStudio-Image-Sequence-\(UUID().uuidString).zip")
        try ZipArchive.create(fromDirectory: folder, to: archive)
        return archive
    }
}
