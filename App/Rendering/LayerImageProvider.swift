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
    /// Export and RAM pre-render use zero tolerance to avoid repeated neighbouring video frames.
    let exactVideoFrame: Bool
    let interpolateSlowMotion: Bool
}

private struct ProcessKey: Hashable {
    let source: SourceKey
    /// The effects with every setting already worked out for this frame. Same input, same output.
    let effects: [ResolvedEffect]
    /// Animated grain/tracking advances at 12 fps, not every 60/120 Hz display refresh.
    let animationPhase: Int64
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
    @ObservationIgnored private var sourceOrder: [SourceKey] = []
    @ObservationIgnored private var requestedVideoFrameTicks: [UUID: Int64] = [:]
    @ObservationIgnored private var playbackPreview = false
    @ObservationIgnored private var loadingSources: Set<SourceKey> = []
    // Video decodes are serial per asset. While one frame is decoding, retain only the newest
    // requested frame instead of starting a backlog of obsolete AVAssetImageGenerator jobs.
    @ObservationIgnored private var loadingVideoAssets: Set<UUID> = []
    @ObservationIgnored private var wantedVideoSources: [UUID: (key: SourceKey, url: URL)] = [:]
    @ObservationIgnored private var missingAssets: Set<UUID> = []
    @ObservationIgnored private var failedSources: Set<SourceKey> = []
    @ObservationIgnored private var processed: [ProcessKey: Processed] = [:]
    @ObservationIgnored private var processedOrder: [ProcessKey] = []
    @ObservationIgnored private var processedCosts: [ProcessKey: Int] = [:]
    @ObservationIgnored private var processedTotalCost = 0
    @ObservationIgnored private var latest: [UUID: Processed] = [:]
    @ObservationIgnored private var runningKeys: [UUID: ProcessKey] = [:]
    @ObservationIgnored private var wanted: [UUID: ProcessJob] = [:]

    // Keep several seconds of processed preview frames where memory allows. This lets a second
    // playback reuse work, like a lightweight RAM preview cache, rather than re-rendering immediately.
    private static let cacheLimit = 120
    private static let processedCostLimit = 96 * 1024 * 1024
    // Decoded frames are cheaper than processed frames, but still bounded to avoid unbounded memory.
    private static let sourceCacheLimit = 72
    private static let largestPreviewSide = 512
    private static let playbackPreviewSide = 320
    private static let playbackVideoFPS: Int64 = 24

    var isBusy: Bool { !loadingSources.isEmpty || !runningKeys.isEmpty || !wanted.isEmpty || !wantedVideoSources.isEmpty }

    // MARK: Setup

    /// Tells the provider which images the project has and where the project folder is.
    func configure(assets list: [Asset], folderURL: URL) {
        var map: [UUID: Asset] = [:]
        for asset in list { map[asset.id] = asset }
        if folder != folderURL {
            sources.removeAll()
            sourceOrder.removeAll()
            processed.removeAll()
            processedOrder.removeAll()
            processedCosts.removeAll()
            processedTotalCost = 0
            latest.removeAll()
            missingAssets.removeAll()
            failedSources.removeAll()
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
        sourceOrder.removeAll { $0.assetID == assetID }
        let removedKeys = processed.keys.filter { $0.source.assetID == assetID }
        for key in removedKeys {
            processed[key] = nil
            processedTotalCost -= processedCosts.removeValue(forKey: key) ?? 0
        }
        processedOrder.removeAll { $0.source.assetID == assetID }
        missingAssets.remove(assetID)
        failedSources = failedSources.filter { $0.assetID != assetID }
    }

    // MARK: Asking for pictures (called while the preview is being built)

    func provideAll(for frame: ResolvedFrame,
                    playbackPreview: Bool = false,
                    exportQuality: Bool = false,
                    exactVideoFrames: Bool = false) -> [UUID: ProvidedImage] {
        self.playbackPreview = playbackPreview
        // Video frame caches are bounded by LRU below. Do not purge every previous frame here:
        // sequential playback would otherwise throw away the exact frames that could be reused.
        var result: [UUID: ProvidedImage] = [:]
        for layer in frame.layers {
            switch layer.kind {
            case .image, .video:
                result[layer.id] = provide(layer, at: frame.time,
                                           exportMaxSide: exportQuality ? max(frame.width, frame.height) : nil,
                                           exactVideoFrame: exportQuality || exactVideoFrames)
            default:
                break
            }
        }
        return result
    }

    func provide(_ layer: ResolvedLayer,
                 at time: MotionCore.Time = .zero,
                 exportMaxSide: Int? = nil,
                 exactVideoFrame: Bool = false) -> ProvidedImage {
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
        let previewLimit = exportMaxSide ?? (playbackPreview ? Self.playbackPreviewSide : Self.largestPreviewSide)
        let maxPixel = min(previewLimit, max(64, Int(longestSide.rounded(.up))))
        let mappedVideoTicks = isVideo ? Int64(max(0, (layer.videoSourceTimeSeconds ?? time.seconds) * Double(MotionCore.Time.ticksPerSecond)).rounded()) : nil
        let videoTicks = isVideo ? (playbackPreview ? quantizedVideoTicks(mappedVideoTicks ?? time.ticks) : mappedVideoTicks) : nil
        if isVideo, let videoTicks { requestedVideoFrameTicks[assetID] = videoTicks }
        let flowEnabled = isVideo && layer.effects.contains(where: { $0.effectID == "optical-flow-slow-motion" }) && layer.playbackSpeed < 0.999
        let sourceKey = SourceKey(assetID: assetID, maxPixel: maxPixel, frameTicks: videoTicks,
                                  exactVideoFrame: isVideo && exactVideoFrame,
                                  interpolateSlowMotion: flowEnabled && exactVideoFrame)
        if failedSources.contains(sourceKey) { return .missing }
        let layerRect = CGRect(x: 0, y: 0, width: layer.size.x, height: layer.size.y)

        // Build the processed-frame key before decoding. A cached render should be usable even
        // after its original decoded source frame has been evicted from the smaller source cache.
        let hasEffects = EffectPipeline.hasWork(layer.effects) && layer.size.x > 0
        let animatedEffects = layer.effects.map { effect -> ResolvedEffect in
            guard effect.effectID == "noise" else { return effect }
            var copy = effect
            let original = copy.values["seed"]?.first ?? 1
            let phase = Int64(max(0, floor(time.seconds * 12)))
            copy.values["seed"] = [Double((Int64(original.rounded()) + phase) % 10_001)]
            return copy
        }
        let hasAnimatedEffect = animatedEffects.contains { $0.effectID == "noise" || $0.effectID == "vhs" }
        let animationPhase = hasAnimatedEffect ? Int64(max(0, floor(time.seconds * 12))) : 0
        let processKey = ProcessKey(source: sourceKey, effects: animatedEffects, animationPhase: animationPhase)
        if hasEffects, let hit = processed[processKey] {
            processedOrder.removeAll { $0 == processKey }
            processedOrder.append(processKey)
            latest[layer.id] = hit
            return .ready(image: hit.image, rect: hit.rect)
        }

        let source: CGImage
        if let cached = sources[sourceKey] {
            sourceOrder.removeAll { $0 == sourceKey }
            sourceOrder.append(sourceKey)
            source = cached
        } else {
            requestSource(sourceKey, url: url)
            // Exact frame requests must never fall back to a previous video frame: doing so creates
            // duplicated frames in exported footage when a seek is slow or fails.
            if !sourceKey.exactVideoFrame, let previous = latest[layer.id] {
                return .ready(image: previous.image, rect: previous.rect)
            }
            return .loading
        }
        guard hasEffects else {
            let ready = Processed(image: source, rect: layerRect)
            latest[layer.id] = ready
            return .ready(image: source, rect: layerRect)
        }

        // Bitmap pixels per layer pixel: effect settings are written in layer pixels.
        requestProcessing(layerID: layer.id, key: processKey, source: source,
                          scale: Double(source.width) / layer.size.x)
        if let previous = latest[layer.id] { return .ready(image: previous.image, rect: previous.rect) }
        return .ready(image: source, rect: layerRect)
    }

    /// Playback preview deliberately samples video at a bounded rate. Decoding a unique frame
    /// for every display-link tick can queue expensive AVAssetImageGenerator work faster than it finishes.
    private func quantizedVideoTicks(_ ticks: Int64) -> Int64 {
        let interval = max(1, MotionCore.Time.ticksPerSecond / Self.playbackVideoFPS)
        return (ticks / interval) * interval
    }

    // MARK: Loading

    private func requestSource(_ key: SourceKey, url: URL) {
        guard !loadingSources.contains(key) else { return }
        if key.frameTicks != nil {
            // AVAssetImageGenerator is expensive. Do not run many concurrent decodes for the
            // same clip while the playhead advances; replace the queued request with the newest.
            if loadingVideoAssets.contains(key.assetID) {
                wantedVideoSources[key.assetID] = (key, url)
                return
            }
            loadingVideoAssets.insert(key.assetID)
        }
        loadingSources.insert(key)
        Task { [weak self] in
            let image = await Task.detached(priority: .userInitiated) {
                let timestamp = key.frameTicks.map { Double($0) / Double(MotionCore.Time.ticksPerSecond) }
                if key.interpolateSlowMotion, let timestamp {
                    return await VideoFrameGeneratorPool.interpolatedImage(url: url, maxPixel: key.maxPixel, seconds: timestamp)
                }
                return await LayerImageProvider.decode(url: url, maxPixel: key.maxPixel, videoTime: timestamp, exactVideoFrame: key.exactVideoFrame)
            }.value
            self?.sourceLoaded(key, image)
        }
    }

    private func sourceLoaded(_ key: SourceKey, _ image: CGImage?) {
        loadingSources.remove(key)
        if key.frameTicks != nil { loadingVideoAssets.remove(key.assetID) }
        let isCurrentVideoFrame = key.frameTicks == nil || key.frameTicks == requestedVideoFrameTicks[key.assetID]
        if let image {
            failedSources.remove(key)
            // Cache still images and recent video frames. LRU eviction keeps memory bounded.
            sources[key] = image
            sourceOrder.removeAll { $0 == key }
            sourceOrder.append(key)
            while sourceOrder.count > Self.sourceCacheLimit {
                let oldest = sourceOrder.removeFirst()
                sources[oldest] = nil
            }
        } else if key.frameTicks != nil {
            // Keep the failed frame distinct from the asset: later timestamps in the same clip can work.
            failedSources.insert(key)
        } else if isCurrentVideoFrame {
            missingAssets.insert(key.assetID)
        }
        version += 1

        // If the playhead moved during decoding, decode only the newest queued frame next.
        if let next = wantedVideoSources.removeValue(forKey: key.assetID),
           next.key != key, next.key.frameTicks == requestedVideoFrameTicks[key.assetID] {
            requestSource(next.key, url: next.url)
        }
    }

    /// A reduced-size copy with the photo's rotation applied. Never decodes more than `maxPixel` on the long side.
    nonisolated private static func decode(url: URL, maxPixel: Int, videoTime: Double?, exactVideoFrame: Bool) async -> CGImage? {
        if let videoTime {
            return await videoPoster(url: url, maxPixel: maxPixel, seconds: videoTime, exact: exactVideoFrame)
        }
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

    nonisolated private static func videoPoster(url: URL, maxPixel: Int, seconds: Double, exact: Bool) async -> CGImage? {
        await VideoFrameGeneratorPool.image(url: url, maxPixel: maxPixel, seconds: seconds, exact: exact)
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
                // Prefer a single GPU-backed Core Image graph for common effects. This avoids
                // converting every pixel into Float arrays and back on the CPU.
                if CoreImageEffectRenderer.canRender(effects),
                   let image = CoreImageEffectRenderer.render(source, effects: effects, scale: scale,
                                                              animationPhase: Double(job.key.animationPhase)) {
                    return ProcessResult(image: image,
                                         rect: CGRect(x: 0, y: 0, width: Double(image.width) / scale,
                                                      height: Double(image.height) / scale),
                                         issues: [])
                }
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
            if let previousCost = processedCosts[key] { processedTotalCost -= previousCost }
            let cost = max(1, result.image.bytesPerRow * result.image.height)
            processed[key] = item
            processedCosts[key] = cost
            processedTotalCost += cost
            processedOrder.removeAll { $0 == key }
            processedOrder.append(key)
            while processedOrder.count > Self.cacheLimit || processedTotalCost > Self.processedCostLimit {
                let oldest = processedOrder.removeFirst()
                processed[oldest] = nil
                processedTotalCost -= processedCosts.removeValue(forKey: oldest) ?? 0
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
