import AVFoundation
import CoreGraphics
import Foundation
import Vision

/// Reuses generators and requests frames asynchronously. This keeps decode work out of the
/// preview's synchronous path and allows AVFoundation to schedule its own decode work.
/// This is still a frame-extraction fallback, not a replacement for AVPlayerItemVideoOutput.
enum VideoFrameGeneratorPool {
    private final class Box: NSObject {
        let generator: AVAssetImageGenerator

        init(url: URL, maxPixel: Int, exact: Bool) {
            let asset = AVURLAsset(url: url)
            generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: maxPixel, height: maxPixel)
            // Interactive preview tolerates nearby frames to keep scrubbing responsive. Pre-render
            // and export request exact timestamps so adjacent output frames are not duplicated.
            generator.requestedTimeToleranceBefore = exact ? .zero : CMTime(value: 1, timescale: 12)
            generator.requestedTimeToleranceAfter = exact ? .zero : CMTime(value: 1, timescale: 12)
        }

        func image(at time: CMTime) async -> CGImage? {
            await withCheckedContinuation { continuation in
                generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, image, _, result, _ in
                    continuation.resume(returning: result == .succeeded ? image : nil)
                }
            }
        }
    }

    private static let cache: NSCache<NSString, Box> = {
        let cache = NSCache<NSString, Box>()
        cache.countLimit = 12
        return cache
    }()

    /// Reads the two source frames around a sub-frame timestamp and synthesizes the missing
    /// frame with Vision optical flow. Intended for export-time slow motion, not interactive scrubbing.
    static func interpolatedImage(url: URL, maxPixel: Int, seconds: Double) async -> CGImage? {
        let asset = AVURLAsset(url: url)
        let fps = asset.tracks(withMediaType: .video).first.map { Double($0.nominalFrameRate) } ?? 30
        let safeFPS = min(120, max(1, fps.isFinite && fps > 0 ? fps : 30))
        let frameDuration = 1.0 / safeFPS
        let safeSeconds = max(0, seconds.isFinite ? seconds : 0)
        let lower = floor(safeSeconds / frameDuration) * frameDuration
        let fraction = (safeSeconds - lower) / frameDuration
        if fraction < 0.015 { return await image(url: url, maxPixel: maxPixel, seconds: lower, exact: true) }
        let a = await image(url: url, maxPixel: maxPixel, seconds: lower, exact: true)
        let b = await image(url: url, maxPixel: maxPixel, seconds: lower + frameDuration, exact: true)
      guard let a, let b else {
    // If either neighbouring frame fails to decode, do not pretend
    // that a single frame is a valid interpolated frame.
    return nil
}
        return await Task.detached(priority: .userInitiated) {
            OpticalFlowInterpolator.interpolate(a, b, amount: CGFloat(fraction))
        }.value
    }

    static func image(url: URL, maxPixel: Int, seconds: Double, exact: Bool = false) async -> CGImage? {
        let key = "\(url.standardizedFileURL.path)|\(maxPixel)|exact=\(exact)" as NSString
        let box: Box
        if let existing = cache.object(forKey: key) {
            box = existing
        } else {
            let created = Box(url: url, maxPixel: maxPixel, exact: exact)
            cache.setObject(created, forKey: key)
            box = created
        }
        let safeSeconds = max(0, seconds.isFinite ? seconds : 0)
        return await box.image(at: CMTime(seconds: safeSeconds, preferredTimescale: 600))
    }
}
