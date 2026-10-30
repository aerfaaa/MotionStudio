import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import MotionCore
import UIKit

/// Frame-by-frame MP4 export. The same evaluated composition frame and effects pipeline as the
/// preview are used, then timeline audio is muxed into the finished video when present.
enum VideoExportError: LocalizedError {
    case writerUnavailable
    case cannotStart(String)
    case frameNotReady(Int64)
    case renderFailed(Int64)
    case pixelBufferUnavailable
    case appendFailed(String)
    case finishFailed(String)
    case audioMuxFailed(String)

    var errorDescription: String? {
        switch self {
        case .writerUnavailable: return "The MP4 video writer is not available on this device."
        case .cannotStart(let detail): return "The video export could not start. \(detail)"
        case .frameNotReady(let index): return "Media for frame \(index) did not finish loading in time. Wait for the preview to settle and retry."
        case .renderFailed(let index): return "Frame \(index) could not be rendered."
        case .pixelBufferUnavailable: return "A video frame buffer could not be allocated."
        case .appendFailed(let detail): return "A video frame could not be written. \(detail)"
        case .finishFailed(let detail): return "The MP4 could not be finalised. \(detail)"
        case .audioMuxFailed(let detail): return "Video was rendered, but its audio could not be added. \(detail)"
        }
    }
}

enum VideoFrameExporter {
    // Reuse this across every frame instead of creating a colour space for each output buffer.
    private static let sRGBColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    @MainActor
    static func export(width: Int,
                       height: Int,
                       frameRate: FrameRate,
                       frameCount: Int64,
                       layers: [Layer],
                       assets: [Asset],
                       projectFolder: URL,
                       bitrateMbps: Double,
                       frameProvider: @MainActor (Int64) async throws -> UIImage,
                       progress: @MainActor (Int64, Int64) -> Void) async throws -> URL {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("MotionStudio-Export-\(UUID().uuidString).mp4")
        let writer: AVAssetWriter
        do { writer = try AVAssetWriter(outputURL: output, fileType: .mp4) }
        catch { throw VideoExportError.cannotStart(error.localizedDescription) }

        // The user controls the target video bitrate in megabits per second (Mbps).
        // Clamp here as well as in the UI so malformed settings cannot create invalid writer settings.
        let safeBitrateMbps = min(50.0, max(2.0, bitrateMbps.isFinite ? bitrateMbps : 12.0))
        let targetBitrate = Int((safeBitrateMbps * 1_000_000).rounded())
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: targetBitrate,
                AVVideoExpectedSourceFrameRateKey: Int(frameRate.framesPerSecond.rounded()),
                AVVideoMaxKeyFrameIntervalKey: max(1, Int(frameRate.framesPerSecond.rounded()))
            ]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ])
        guard writer.canAdd(input) else { throw VideoExportError.writerUnavailable }
        writer.add(input)
        guard writer.startWriting() else {
            throw VideoExportError.cannotStart(writer.error?.localizedDescription ?? "Unknown writer error.")
        }
        writer.startSession(atSourceTime: .zero)

        do {
            for index in 0..<max(1, frameCount) {
                try Task.checkCancellation()
                let image = try await frameProvider(index)
                while !input.isReadyForMoreMediaData {
                    try Task.checkCancellation()
                    if writer.status == .failed {
                        throw VideoExportError.appendFailed(writer.error?.localizedDescription ?? "Writer failed.")
                    }
                    try await Task.sleep(for: .milliseconds(5))
                }
                guard let cgImage = image.cgImage else { throw VideoExportError.renderFailed(index) }
                guard let pool = adaptor.pixelBufferPool else { throw VideoExportError.pixelBufferUnavailable }
                var optionalBuffer: CVPixelBuffer?
                let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &optionalBuffer)
                guard status == kCVReturnSuccess, let buffer = optionalBuffer else {
                    throw VideoExportError.pixelBufferUnavailable
                }
                CVPixelBufferLockBaseAddress(buffer, [])
                defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
                guard let base = CVPixelBufferGetBaseAddress(buffer),
                      let bitmap = CGContext(data: base, width: width, height: height, bitsPerComponent: 8,
                                             bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                             space: sRGBColorSpace,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue |
                                                CGBitmapInfo.byteOrder32Little.rawValue) else {
                    throw VideoExportError.pixelBufferUnavailable
                }
                bitmap.clear(CGRect(x: 0, y: 0, width: width, height: height))
                bitmap.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
                let presentation = CMTime(value: index * frameRate.denominator, timescale: CMTimeScale(frameRate.numerator))
                guard adaptor.append(buffer, withPresentationTime: presentation) else {
                    throw VideoExportError.appendFailed(writer.error?.localizedDescription ?? "Pixel buffer append failed.")
                }
                progress(index + 1, max(1, frameCount))
            }
            input.markAsFinished()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                writer.finishWriting {
                    if writer.status == .completed { continuation.resume() }
                    else { continuation.resume(throwing: VideoExportError.finishFailed(writer.error?.localizedDescription ?? "Unknown writer error.")) }
                }
            }
        } catch {
            input.markAsFinished()
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: output)
            throw error
        }

        // Add audio clips at their composition in-points. The source media remains untouched.
        let audioLayers = layers.compactMap { layer -> (Layer, UUID, Bool)? in
            switch layer.kind {
            case .audio(let id): return (layer, id, false)
            case .video(let id): return (layer, id, true)
            default: return nil
            }
        }
        guard !audioLayers.isEmpty else { return output }
        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: output)
        guard let sourceVideo = videoAsset.tracks(withMediaType: .video).first,
              let destinationVideo = composition.addMutableTrack(withMediaType: .video,
                                                                  preferredTrackID: kCMPersistentTrackID_Invalid) else {
            return output
        }
        try destinationVideo.insertTimeRange(CMTimeRange(start: .zero, duration: videoAsset.duration),
                                             of: sourceVideo, at: .zero)
        var insertedAudio = false
        var audioMixParameters: [AVAudioMixInputParameters] = []
        for (layer, assetID, isVideo) in audioLayers where layer.isVisible {
            guard let asset = assets.first(where: { $0.id == assetID }),
                  let url = ProjectMedia.fileURL(for: asset, inProjectFolder: projectFolder) else { continue }
            let source = AVURLAsset(url: url)
            guard let sourceTrack = source.tracks(withMediaType: .audio).first,
                  let destinationTrack = composition.addMutableTrack(withMediaType: .audio,
                                                                       preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            let clipLength = max(0, layer.outPoint.seconds - layer.inPoint.seconds)
            let sourceStart = isVideo && layer.sourceOffsetSeconds == 0
                ? max(0, layer.inPoint.seconds) : max(0, layer.sourceOffsetSeconds)
            let available = max(0, source.duration.seconds - sourceStart)
            let duration = min(clipLength, available)
            guard duration > 0 else { continue }
            do {
                try destinationTrack.insertTimeRange(
                    CMTimeRange(start: CMTime(seconds: sourceStart, preferredTimescale: 600),
                                duration: CMTime(seconds: duration, preferredTimescale: 600)),
                    of: sourceTrack,
                    at: CMTime(seconds: layer.inPoint.seconds, preferredTimescale: 600))
                insertedAudio = true
                let mixParameters = AVMutableAudioMixInputParameters(track: destinationTrack)
                mixParameters.setVolume(Float(layer.audioVolume), at: CMTime(seconds: layer.inPoint.seconds, preferredTimescale: 600))
                audioMixParameters.append(mixParameters)
            } catch {
                // Keep exporting other audio clips; a malformed optional clip should not lose the video.
                continue
            }
        }
        // Applying per-layer gain requires an audio mix, so the final mux pass re-encodes the
        // composition at the system's high-quality preset instead of using passthrough.
        guard insertedAudio,
              let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            return output
        }
        let muxed = FileManager.default.temporaryDirectory
            .appendingPathComponent("MotionStudio-Final-\(UUID().uuidString).mp4")
        exporter.outputURL = muxed
        exporter.outputFileType = .mp4
        if !audioMixParameters.isEmpty {
            let audioMix = AVMutableAudioMix()
            audioMix.inputParameters = audioMixParameters
            exporter.audioMix = audioMix
        }
        exporter.shouldOptimizeForNetworkUse = true
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            exporter.exportAsynchronously {
                switch exporter.status {
                case .completed: continuation.resume()
                case .cancelled: continuation.resume(throwing: CancellationError())
                default: continuation.resume(throwing: VideoExportError.audioMuxFailed(exporter.error?.localizedDescription ?? "Unknown audio export error."))
                }
            }
        }
        try? FileManager.default.removeItem(at: output)
        return muxed
    }
}
