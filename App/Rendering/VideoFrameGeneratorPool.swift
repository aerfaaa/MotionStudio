import AVFoundation
import CoreGraphics
import Foundation

/// Reuses generators and requests frames asynchronously. This keeps decode work out of the
/// preview's synchronous path and allows AVFoundation to schedule its own decode work.
/// This is still a frame-extraction fallback, not a replacement for AVPlayerItemVideoOutput.
enum VideoFrameGeneratorPool {
    private final class Box: NSObject {
        let generator: AVAssetImageGenerator

        init(url: URL, maxPixel: Int) {
            let asset = AVURLAsset(url: url)
            generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: maxPixel, height: maxPixel)
            // Wider tolerance lets AVFoundation use a nearby decoded frame instead of forcing
            // expensive exact seeks during interactive preview.
            generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 12)
            generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 12)
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

    static func image(url: URL, maxPixel: Int, seconds: Double) async -> CGImage? {
        let key = "\(url.standardizedFileURL.path)|\(maxPixel)" as NSString
        let box: Box
        if let existing = cache.object(forKey: key) {
            box = existing
        } else {
            let created = Box(url: url, maxPixel: maxPixel)
            cache.setObject(created, forKey: key)
            box = created
        }
        let safeSeconds = max(0, seconds.isFinite ? seconds : 0)
        return await box.image(at: CMTime(seconds: safeSeconds, preferredTimescale: 600))
    }
}
