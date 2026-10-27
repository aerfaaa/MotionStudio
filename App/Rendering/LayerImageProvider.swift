import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import Observation
import MotionCore

/// What the preview should draw for an image layer.
enum ProvidedImage {
    /// `rect` is where to draw the picture, in the layer's own pixels (it can be bigger than the layer
    /// when a shadow or glow has grown the canvas).
    case ready(image: CGImage, rect: CGRect)
    case loading
    case missing
}

private struct SourceKey: Hashable {
    let assetID: UUID
    let maxPixel: Int
    /// Still images use nil. Video thumbnails are keyed by composition frame time.
    let frameTicks: Int64?
}

private struct ProcessKey: Hashable {
    let source: SourceKey
    /// The effects with every setting already worked out for this frame. Same input, same output.
    let effects: [ResolvedEffect]
}

private struct Processed {
    let image: CGImage
    let rect: CGRect
}

private struct ProcessJob {
    let key: ProcessKey
    let scale: Double
}

private struct ProcessResult {
    let image: CGImage
    let rect: CGRect
    let issues: [EffectIssue]
}

/// Supplies the pictures the preview draws for image layers.
///
/// - Loads a reduced-size copy of each image from the project folder (never the full-size photo).
/// - Runs a layer's effects on that copy in the background, so the interface never waits for them.
/// - Remembers results, so the same picture with the same settings is not processed twice.
/// - While a new result is being made, the previous result keeps showing, so there is no flicker.
@MainActor
@Observable
final class LayerImageProvider {
    /// Goes up whenever something finishes loading or processing, so the preview redraws.
    private(set) var version = 0
    /// Problems found while processing a layer's effects, by layer.
    private(set) var issues: [UUID: [EffectIssue]] = [:]

    @ObservationIgnored private var assets: [UUID: Asset] = [:]
    @ObservationIgnored private var folder: URL?
    @ObservationIgnored private var sources: [SourceKey: CGImage] = [:]
    @ObservationIgnored private var requestedFrameTicks: Int64 = 0
    @ObservationIgnored private var loadingSources: Set<SourceKey> = []
    @ObservationIgnored private var missingAssets: Set<UUID> = []
    @ObservationIgnored private var processed: [ProcessKey: Processed] = [:]
    @ObservationIgnored private var processedOrder: [ProcessKey] = []
    @ObservationIgnored private var latest: [UUID: Processed] = [:]
    @ObservationIgnored private var runningKeys: [UUID: ProcessKey] = [:]
    @ObservationIgnored private var wanted: [UUID: ProcessJob] = [:]

    private static let cacheLimit = 24
    private static let largestPreviewSide = 1024

    var isBusy: Bool { !loadingSources.isEmpty || !runningKeys.isEmpty || !wanted.isEmpty }

    // MARK: Setup

    /// Tells the provider which images the project has and where the project folder is.
    func configure(assets list: [Asset], folderURL: URL) {
        var map: [UUID: Asset] = [:]
        for asset in list { map[asset.id] = asset }
        if folder != folderURL {
            sources.removeAll()
            processed.removeAll()
            processedOrder.removeAll()
            latest.removeAll()
            missingAssets.removeAll()
        } else {
            for (id, old) in assets where map[id]?.relativePath != old.relativePath {
                forget(assetID: id)
            }
        }
        assets = map
        folder = folderURL
    }

    private func forget(assetID: UUID) {
        sources = sources.filter { $0.key.assetID != assetID }
        processed = processed.filter { $0.key.source.assetID != assetID }
        processedOrder.removeAll { $0.source.assetID == assetID }
        missingAssets.remove(assetID)
    }

    // MARK: Asking for pictures (called while the preview is being built)

    func provideAll(for frame: ResolvedFrame) -> [UUID: ProvidedImage] {
        requestedFrameTicks = frame.time.ticks
        // Keep still-image decodes, but discard old video frames so scrubbing does not grow memory forever.
        sources = sources.filter { $0.key.frameTicks == nil || $0.key.frameTicks == frame.time.ticks }
        processed = processed.filter { $0.key.source.frameTicks == nil || $0.key.source.frameTicks == frame.time.ticks }
        processedOrder.removeAll { $0.source.frameTicks != nil && $0.source.frameTicks != frame.time.ticks }
        var result: [UUID: ProvidedImage] = [:]
        for layer in frame.layers {
            switch layer.kind {
            case .image, .video:
                result[layer.id] = provide(layer, at: frame.time)
            default:
                break
            }
        }
        return result
    }

    func provide(_ layer: ResolvedLayer, at time: MotionCore.Time = .zero) -> ProvidedImage {
        let assetID: UUID
        let isVideo: Bool
        switch layer.kind {
        case .image(let id): assetID = id; isVideo = false
        case .video(let id): assetID = id; isVideo = true
        default: return .missing
        }
        guard let asset = assets[assetID], let folder else { return .missing }
        if missingAssets.contains(assetID) { return .missing }
        guard let url = ProjectMedia.fileURL(for: asset, inProjectFolder: folder) else {
            missingAssets.insert(assetID)
            return .missing
        }

        let longestSide = max(layer.size.x, layer.size.y)
        let maxPixel = min(Self.largestPreviewSide, max(64, Int(longestSide.rounded(.up))))
        let sourceKey = SourceKey(assetID: assetID, maxPixel: maxPixel,
                                  frameTicks: isVideo ? time.ticks : nil)
        let layerRect = CGRect(x: 0, y: 0, width: layer.size.x, height: layer.size.y)

        guard let source = sources[sourceKey] else {
            requestSource(sourceKey, url: url)
            if let previous = latest[layer.id] { return .ready(image: previous.image, rect: previous.rect) }
            return .loading
        }
        guard EffectPipeline.hasWork(layer.effects), layer.size.x > 0 else {
            let ready = Processed(image: source, rect: layerRect)
            latest[layer.id] = ready
            return .ready(image: source, rect: layerRect)
        }

        let key = ProcessKey(source: sourceKey, effects: layer.effects)
        if let hit = processed[key] {
            latest[layer.id] = hit
            return .ready(image: hit.image, rect: hit.rect)
        }
        // Bitmap pixels per layer pixel: effect settings are written in layer pixels.
        requestProcessing(layerID: layer.id, key: key, source: source, scale: Double(source.width) / layer.size.x)
        if let previous = latest[layer.id] { return .ready(image: previous.image, rect: previous.rect) }
        return .ready(image: source, rect: layerRect)
    }

    // MARK: Loading

    private func requestSource(_ key: SourceKey, url: URL) {
        guard !loadingSources.contains(key) else { return }
        loadingSources.insert(key)
        Task { [weak self] in
            let image = await Task.detached(priority: .userInitiated) {
                LayerImageProvider.decode(url: url, maxPixel: key.maxPixel,
                                          videoTime: key.frameTicks.map { Double($0) / Double(MotionCore.Time.ticksPerSecond) })
            }.value
            self?.sourceLoaded(key, image)
        }
    }

    private func sourceLoaded(_ key: SourceKey, _ image: CGImage?) {
        loadingSources.remove(key)
        let isCurrentVideoFrame = key.frameTicks == nil || key.frameTicks == requestedFrameTicks
        if let image {
            if isCurrentVideoFrame { sources[key] = image }
        } else if isCurrentVideoFrame {
            missingAssets.insert(key.assetID)
        }
        version += 1
    }

    /// A reduced-size copy with the photo's rotation applied. Never decodes more than `maxPixel` on the long side.
    nonisolated private static func decode(url: URL, maxPixel: Int, videoTime: Double?) -> CGImage? {
        if let videoTime { return videoPoster(url: url, maxPixel: maxPixel, seconds: videoTime) }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        var limit = maxPixel
        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? Int,
           let height = properties[kCGImagePropertyPixelHeight] as? Int {
            limit = min(maxPixel, max(width, height))      // never enlarge a small picture
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(limit, 1),
        ]
        if let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) { return image }
        return nil
    }

    nonisolated private static func videoPoster(url: URL, maxPixel: Int, seconds: Double) -> CGImage? {
        let asset = AVURLAsset(url: url)
        guard !asset.tracks(withMediaType: .video).isEmpty else { return nil }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixel, height: maxPixel)
        let duration = asset.duration.seconds
        let safeTime = max(0, min(seconds, duration.isFinite && duration > 0 ? max(0, duration - 1.0 / 60.0) : 0))
        return try? generator.copyCGImage(at: CMTime(seconds: safeTime, preferredTimescale: 600), actualTime: nil)
    }

    // MARK: Processing

    private func requestProcessing(layerID: UUID, key: ProcessKey, source: CGImage, scale: Double) {
        if runningKeys[layerID] == key || wanted[layerID]?.key == key { return }
        wanted[layerID] = ProcessJob(key: key, scale: scale)
        if runningKeys[layerID] == nil { startJob(layerID) }
    }

    private func startJob(_ layerID: UUID) {
        guard let job = wanted.removeValue(forKey: layerID), let source = sources[job.key.source] else { return }
        runningKeys[layerID] = job.key
        let effects = job.key.effects
        let scale = job.scale
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { () -> ProcessResult? in
                guard let pixels = PixelBridge.makePixelImage(from: source) else { return nil }
                let output = EffectPipeline.apply(effects, to: pixels, scale: scale)
                guard let image = PixelBridge.makeCGImage(from: output.image) else { return nil }
                let rect = CGRect(x: Double(output.image.originX) / scale, y: Double(output.image.originY) / scale,
                                  width: Double(output.image.width) / scale, height: Double(output.image.height) / scale)
                return ProcessResult(image: image, rect: rect, issues: output.issues)
            }.value
            self?.jobFinished(layerID: layerID, key: job.key, result: result)
        }
    }

    private func jobFinished(layerID: UUID, key: ProcessKey, result: ProcessResult?) {
        runningKeys[layerID] = nil
        if let result {
            let item = Processed(image: result.image, rect: result.rect)
            processed[key] = item
            processedOrder.removeAll { $0 == key }
            processedOrder.append(key)
            while processedOrder.count > Self.cacheLimit {
                processed[processedOrder.removeFirst()] = nil
            }
            latest[layerID] = item
            issues[layerID] = result.issues
        } else {
            issues[layerID] = [EffectIssue(effectID: "", message: "The effects could not be applied to this picture.")]
        }
        version += 1
        // Settings may have changed again while this job ran: process the newest ones.
        if wanted[layerID] != nil { startJob(layerID) }
    }
}
