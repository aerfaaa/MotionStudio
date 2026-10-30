import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import AVFoundation
import MotionCore
import Observation
import QuartzCore

enum SaveState: Equatable {
    case saved
    case unsaved
    case failed
}

/// Points at one keyframe: which layer, which property, and when.
struct KeyframeRef: Equatable {
    var layerID: UUID
    var property: PropertyKey
    var time: Time
}

enum NewLayerKind {
    case rectangle
    case ellipse
    case solid
    case text
    case null
    case adjustment
}

/// The bridge between the screen and MotionCore.
///
/// Views read from this object and call its methods. Every change is turned into a MotionCore
/// `Command`, so undo and redo, saving and keyframes all behave the same however an edit starts.
@MainActor
@Observable
final class EditorModel {

    // MARK: What the screen shows

    private(set) var project: Project
    var selectedLayerID: UUID?
    private(set) var currentFrame: Int64 = 0
    private(set) var isPlaying = false
    var loopPlayback = true
    private(set) var canUndo = false
    private(set) var canRedo = false
    private(set) var undoName: String?
    private(set) var redoName: String?
    private(set) var saveState: SaveState = .saved
    var lastError: String?
    /// The keyframe being edited, if any.
    private(set) var selectedKeyframe: KeyframeRef?
    /// Prepares the pictures (and effect results) the preview draws for image layers.
    let images = LayerImageProvider()
    /// Version changes when a composited preview frame is added or evicted.
    private(set) var previewCacheVersion = 0
    /// Incremented for content edits so pre-render jobs can discard stale results.
    private(set) var previewRevision = 0
    /// True while a picture is being checked and copied into the project.
    private(set) var isImporting = false
    private(set) var customFontNames: [String] = []
    /// The effect being edited in the Effects panel.
    var selectedEffectID: UUID?
    /// The last copied keyframe, ready to paste.
    private(set) var copiedKeyframe: (property: PropertyKey, snapshot: KeyframeSnapshot)?

    // MARK: Internals (not watched by the UI)

    @ObservationIgnored private let document: Document
    @ObservationIgnored let folderURL: URL
    @ObservationIgnored private var clock: PlaybackClock?
    @ObservationIgnored private let driver = DisplayLinkDriver()
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var audioPlayers: [UUID: AVAudioPlayer] = [:]
    @ObservationIgnored private var previewFrames: [Int64: CGImage] = [:]
    @ObservationIgnored private var previewFrameOrder: [Int64] = []
    @ObservationIgnored private var previewFrameCosts: [Int64: Int] = [:]
    @ObservationIgnored private var previewFrameTotalCost = 0
    @ObservationIgnored private var previewDiskFrames: Set<Int64> = []
    @ObservationIgnored private var previewDiskOrder: [Int64] = []
    @ObservationIgnored private var previewDiskCosts: [Int64: Int] = [:]
    @ObservationIgnored private var previewDiskTotalCost = 0
    @ObservationIgnored private let previewDiskDirectory: URL
    private let previewFrameCacheLimit = 48
    private let previewFrameMemoryLimit = 36 * 1024 * 1024
    private let previewDiskLimit = 180 * 1024 * 1024

    init(project: Project, folderURL: URL) {
        self.project = project
        self.document = Document(project: project)
        self.folderURL = folderURL
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        previewDiskDirectory = caches.appendingPathComponent("MotionStudioPreviewCache", isDirectory: true)
            .appendingPathComponent(folderURL.lastPathComponent, isDirectory: true)
        try? FileManager.default.createDirectory(at: previewDiskDirectory, withIntermediateDirectories: true)
        // Preview snapshots are disposable. Clear them when opening a session so a previous edit
        // can never be mistaken for the current project revision.
        if let files = try? FileManager.default.contentsOfDirectory(at: previewDiskDirectory, includingPropertiesForKeys: nil) {
            for file in files { try? FileManager.default.removeItem(at: file) }
        }
        images.configure(assets: project.assets, folderURL: folderURL)
        for asset in project.assets where asset.kind == .font {
            if let url = ProjectMedia.fileURL(for: asset, inProjectFolder: folderURL) {
                customFontNames.append(contentsOf: FontRegistrar.register(url: url))
            }
        }
        customFontNames = Array(Set(customFontNames)).sorted()
    }

    // MARK: Convenient values

    var composition: Composition { project.rootComposition }
    var compositionID: UUID { project.rootCompositionID }
    var frameCount: Int64 { composition.frameCount }
    var currentTime: Time { composition.frameRate.time(ofFrame: currentFrame) }
    var selectedLayer: Layer? {
        guard let id = selectedLayerID else { return nil }
        return composition.layer(withID: id)
    }

    /// What the renderer draws right now.
    var resolvedFrame: ResolvedFrame {
        Evaluator.resolve(composition, frame: currentFrame)
    }

    /// Frame indices with a rendered snapshot in RAM or the bounded on-disk preview cache.
    var cachedPreviewFrameIndices: Set<Int64> { Set(previewDiskFrames).union(previewFrameOrder) }

    func hasCachedPreviewFrame(at frame: Int64) -> Bool {
        previewFrames[frame] != nil || previewDiskFrames.contains(frame)
    }

    func cachedPreviewImage(at frame: Int64, allowDiskRead: Bool = true) -> CGImage? {
        if let image = previewFrames[frame] {
            touchMemoryFrame(frame)
            return image
        }

        // Disk JPEG decoding is synchronous. During playback, never block the main thread
        // waiting for it; a live frame is preferable to a dropped frame.
        guard allowDiskRead, previewDiskFrames.contains(frame) else { return nil }
        guard let source = CGImageSourceCreateWithURL(previewDiskURL(for: frame) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            removeDiskFrame(frame)
            return nil
        }
        cachePreviewImageInMemory(image, at: frame)
        return image
    }

    /// The full-resolution render is never replaced by this cache. These low-resolution snapshots
    /// are for smooth interactive playback only; the export pipeline still renders at output size.
    func storePreviewFrame(_ image: CGImage, at frame: Int64) async {
        cachePreviewImageInMemory(image, at: frame)
        previewCacheVersion += 1
        let destination = previewDiskURL(for: frame)
        let encodedSize = await Task.detached(priority: .utility) { () -> Int? in
            let data = NSMutableData()
            guard let destinationEncoder = CGImageDestinationCreateWithData(
                data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(destinationEncoder, image,
                                       [kCGImageDestinationLossyCompressionQuality: 0.84] as CFDictionary)
            guard CGImageDestinationFinalize(destinationEncoder) else { return nil }
            do {
                try (data as Data).write(to: destination, options: .atomic)
                return data.length
            } catch { return nil }
        }.value
        guard let encodedSize else { return }
        if let oldCost = previewDiskCosts[frame] { previewDiskTotalCost -= oldCost }
        previewDiskFrames.insert(frame)
        previewDiskOrder.removeAll { $0 == frame }
        previewDiskOrder.append(frame)
        previewDiskCosts[frame] = encodedSize
        previewDiskTotalCost += encodedSize
        while previewDiskTotalCost > previewDiskLimit, let oldest = previewDiskOrder.first {
            removeDiskFrame(oldest)
        }
        previewCacheVersion += 1
    }

    private func cachePreviewImageInMemory(_ image: CGImage, at frame: Int64) {
        let cost = max(1, image.bytesPerRow * image.height)
        if let oldCost = previewFrameCosts[frame] { previewFrameTotalCost -= oldCost }
        previewFrames[frame] = image
        previewFrameCosts[frame] = cost
        previewFrameTotalCost += cost
        touchMemoryFrame(frame)
        while previewFrameOrder.count > previewFrameCacheLimit || previewFrameTotalCost > previewFrameMemoryLimit {
            guard let oldest = previewFrameOrder.first else { break }
            previewFrameOrder.removeFirst()
            previewFrames[oldest] = nil
            previewFrameTotalCost -= previewFrameCosts.removeValue(forKey: oldest) ?? 0
        }
    }

    private func touchMemoryFrame(_ frame: Int64) {
        previewFrameOrder.removeAll { $0 == frame }
        previewFrameOrder.append(frame)
    }

    private func previewDiskURL(for frame: Int64) -> URL {
        previewDiskDirectory.appendingPathComponent("frame-\(frame).jpg")
    }

    private func removeDiskFrame(_ frame: Int64) {
        previewDiskFrames.remove(frame)
        previewDiskOrder.removeAll { $0 == frame }
        previewDiskTotalCost -= previewDiskCosts.removeValue(forKey: frame) ?? 0
        try? FileManager.default.removeItem(at: previewDiskURL(for: frame))
    }

    private func invalidatePreviewFrames() {
        previewFrames.removeAll(keepingCapacity: true)
        previewFrameOrder.removeAll(keepingCapacity: true)
        previewFrameCosts.removeAll(keepingCapacity: true)
        previewFrameTotalCost = 0
        previewDiskFrames.removeAll(keepingCapacity: true)
        previewDiskOrder.removeAll(keepingCapacity: true)
        previewDiskCosts.removeAll(keepingCapacity: true)
        previewDiskTotalCost = 0
        if let files = try? FileManager.default.contentsOfDirectory(at: previewDiskDirectory, includingPropertiesForKeys: nil) {
            for file in files { try? FileManager.default.removeItem(at: file) }
        }
        previewRevision += 1
        previewCacheVersion += 1
    }

    // MARK: Selection and layers

    func select(_ id: UUID?) {
        if selectedLayerID != id { selectedEffectID = nil }
        selectedLayerID = id
        if selectedKeyframe?.layerID != id { selectedKeyframe = nil }
    }

    func addLayer(_ kind: NewLayerKind) {
        let comp = composition
        let color = LayerPalette.colors[comp.layers.count % LayerPalette.colors.count]
        let base = Double(min(comp.width, comp.height))
        let layer: Layer
        switch kind {
        case .rectangle:
            layer = Layer(name: nextName("Rectangle"), kind: .shape(.rectangle),
                          size: Vec2(x: base * 0.42, y: base * 0.30), fill: color,
                          inPoint: .zero, outPoint: comp.duration, position: comp.center)
        case .ellipse:
            layer = Layer(name: nextName("Ellipse"), kind: .shape(.ellipse),
                          size: Vec2(x: base * 0.34, y: base * 0.34), fill: color,
                          inPoint: .zero, outPoint: comp.duration, position: comp.center)
        case .solid:
            layer = Layer(name: nextName("Solid"), kind: .solid,
                          size: Vec2(x: Double(comp.width), y: Double(comp.height)), fill: color,
                          inPoint: .zero, outPoint: comp.duration, position: comp.center)
        case .text:
            layer = Layer(name: nextName("Text"), kind: .text("Double-tap to edit text"),
                          size: Vec2(x: base * 0.65, y: base * 0.18), fill: color,
                          inPoint: .zero, outPoint: comp.duration, position: comp.center)
        case .null:
            layer = Layer(name: nextName("Null"), kind: .null,
                          size: Vec2(x: 1, y: 1), fill: color,
                          inPoint: .zero, outPoint: comp.duration, position: comp.center)
        case .adjustment:
            // Index zero is topmost, so this layer affects every visual layer below it.
            layer = Layer(name: nextName("Adjustment Layer"), kind: .adjustment,
                          size: Vec2(x: Double(comp.width), y: Double(comp.height)), fill: .white,
                          inPoint: .zero, outPoint: comp.duration, position: comp.center)
        }
        run(AddLayer(compositionID: compositionID, layer: layer, index: 0))
        selectedLayerID = layer.id
    }

    func deleteSelected() {
        guard let id = selectedLayerID else { return }
        run(RemoveLayer(compositionID: compositionID, layerID: id))
    }

    /// Reorders a layer in the composition stack (index 0 is the topmost layer).
    /// The edit is a normal command, so it participates in undo/redo and project saving.
    func reorderLayer(_ layerID: UUID, to newIndex: Int) {
        guard let oldIndex = composition.index(ofLayer: layerID),
              !composition.layers.isEmpty else { return }
        let safeIndex = min(max(newIndex, 0), composition.layers.count - 1)
        guard oldIndex != safeIndex else { return }
        run(ReorderLayer(compositionID: compositionID, layerID: layerID, newIndex: safeIndex))
        selectedLayerID = layerID
        MotionStudioHaptics.selection()
    }

    func moveLayer(_ layerID: UUID, by offset: Int) {
        guard let index = composition.index(ofLayer: layerID) else { return }
        reorderLayer(layerID, to: index + offset)
    }

    func duplicateSelected() {
        guard let original = selectedLayer else { return }
        var copy = original
        copy.id = UUID()
        copy.name = original.name + " copy"
        if !copy.position.isAnimated {
            copy.position.staticValue = copy.position.staticValue + Vec2(x: 40, y: 40)
        }
        let index = composition.index(ofLayer: original.id) ?? 0
        run(AddLayer(compositionID: compositionID, layer: copy, index: index))
        selectedLayerID = copy.id
    }

    func setParent(_ layerID: UUID, to parentID: UUID?) {
        run(SetLayerParent(compositionID: compositionID, layerID: layerID, parentID: parentID))
    }

    func rename(_ layerID: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        run(RenameLayer(compositionID: compositionID, layerID: layerID, newName: trimmed))
    }

    func setVisibility(_ layerID: UUID, to isVisible: Bool) {
        run(SetLayerVisibility(compositionID: compositionID, layerID: layerID, isVisible: isVisible))
    }

    func setFill(_ layerID: UUID, to fill: RGBA) {
        run(SetLayerFill(compositionID: compositionID, layerID: layerID, fill: fill))
    }

    func setBlendMode(_ layerID: UUID, to mode: BlendMode) {
        run(SetLayerBlendMode(compositionID: compositionID, layerID: layerID, blendMode: mode))
    }

    func setTimelineColor(_ layerID: UUID, to color: RGBA?) {
        run(SetLayerTimelineColor(compositionID: compositionID, layerID: layerID, color: color))
    }

    func setAudioVolume(_ layerID: UUID, to volume: Double) {
        run(SetLayerAudioVolume(compositionID: compositionID, layerID: layerID, volume: volume))
        audioPlayers[layerID]?.volume = Float(min(max(volume, 0), 1))
    }

    /// Splits the selected clip at the current frame. The original becomes the left segment; a copy
    /// becomes the right segment, preserving its appearance, effects, transform and audio gain.
    func splitSelectedAtPlayhead() {
        guard let original = selectedLayer else { return }
        let splitTime = composition.frameRate.time(ofFrame: composition.frameRate.frameIndex(at: currentTime))
        guard splitTime > original.inPoint, splitTime < original.outPoint else {
            lastError = "Move the playhead inside the selected clip before splitting it."
            return
        }
        var right = original
        right.id = UUID()
        right.name = original.name + " (split)"
        right.inPoint = splitTime
        let splitOffset = max(0, splitTime.seconds - original.inPoint.seconds)
        let isVideo: Bool = { if case .video = original.kind { return true }; return false }()
        right.sourceOffsetSeconds = original.sourceOffsetSeconds + splitOffset * (isVideo ? original.playbackSpeed : 1)
        let oldOut = original.outPoint
        setLayerTiming(original.id, inPoint: original.inPoint, outPoint: splitTime, coalescing: false)
        run(AddLayer(compositionID: compositionID, layer: right, index: (composition.index(ofLayer: original.id) ?? 0)))
        setLayerTiming(right.id, inPoint: splitTime, outPoint: oldOut, coalescing: false)
        selectedLayerID = right.id
    }

    /// Adds a freehand vector stroke. Input points are in composition pixel coordinates.
    func addVectorDrawing(points: [Vec2]) {
        guard points.count >= 2 else { return }
        let minX = points.map(\.x).min() ?? 0, maxX = points.map(\.x).max() ?? 0
        let minY = points.map(\.y).min() ?? 0, maxY = points.map(\.y).max() ?? 0
        let width = max(2, maxX - minX), height = max(2, maxY - minY)
        let localPoints = points.map { Vec2(x: $0.x - minX, y: $0.y - minY) }
        let color = LayerPalette.colors[composition.layers.count % LayerPalette.colors.count]
        let layer = Layer(name: nextName("Vector Drawing"), kind: .vectorPath(points: localPoints),
                          size: Vec2(x: width, y: height), fill: color, inPoint: .zero,
                          outPoint: composition.duration, position: Vec2(x: minX + width / 2, y: minY + height / 2))
        run(AddLayer(compositionID: compositionID, layer: layer, index: 0))
        selectedLayerID = layer.id
    }

    func setPlaybackSpeed(_ layerID: UUID, to speed: Double) {
        run(SetLayerPlaybackSpeed(compositionID: compositionID, layerID: layerID, speed: speed,
                                  coalescingKey: "speed-\(layerID.uuidString)"))
    }

    // MARK: Editing values

    /// While a finger drags a layer, every movement is merged into one undo step.
    func movePosition(of layerID: UUID, to value: Vec2) {
        run(SetVectorProperty(compositionID: compositionID, layerID: layerID, property: .position,
                              time: currentTime, value: value,
                              coalescingKey: "drag-\(layerID.uuidString)"))
    }

    func setVector(_ key: PropertyKey, of layerID: UUID, to value: Vec2, coalescing: Bool) {
        run(SetVectorProperty(compositionID: compositionID, layerID: layerID, property: key,
                              time: currentTime, value: value,
                              coalescingKey: coalescing ? "edit-\(layerID.uuidString)-\(key.rawValue)" : nil))
    }

    func setScalar(_ key: PropertyKey, of layerID: UUID, to value: Double, coalescing: Bool) {
        run(SetScalarProperty(compositionID: compositionID, layerID: layerID, property: key,
                              time: currentTime, value: value,
                              coalescingKey: coalescing ? "edit-\(layerID.uuidString)-\(key.rawValue)" : nil))
    }

    /// Call when a drag or slider movement ends.
    func endEditGroup() {
        document.endGroup()
    }

    /// Adds a keyframe at the current frame, or removes the one that is there.
    func toggleKeyframe(_ key: PropertyKey, layerID: UUID) {
        guard let layer = composition.layer(withID: layerID) else { return }
        let time = currentTime
        if layer.hasKeyframe(key, at: time) {
            run(RemoveKeyframe(compositionID: compositionID, layerID: layerID, property: key, time: time))
        } else {
            run(AddKeyframe(compositionID: compositionID, layerID: layerID, property: key, time: time))
        }
    }

    // MARK: Importing pictures

    /// Imports a picture chosen in the Files app.
    func importImage(fromFile url: URL) {
        beginImport { folder in try ImageImporter.importFile(from: url, projectFolder: folder) }
    }

    /// Imports a batch of images in order. The picker can return many files; process them one by one
    /// to avoid multiple concurrent imports racing over the model's selection and progress state.
    func importImages(fromFiles urls: [URL]) {
        guard !urls.isEmpty, !isImporting else { return }
        isImporting = true
        let folder = folderURL
        Task {
            for url in urls {
                do {
                    let asset = try await Task.detached(priority: .userInitiated) {
                        try ImageImporter.importFile(from: url, projectFolder: folder)
                    }.value
                    addImageLayer(for: asset)
                } catch {
                    lastError = "Could not import \(url.lastPathComponent): \(error.localizedDescription)"
                }
            }
            isImporting = false
        }
    }

    /// Imports image, video, audio and font files chosen through the system document picker.
    /// Each file is processed serially so security-scoped URLs and selection state cannot race.
    func importMedia(fromFiles urls: [URL]) {
        guard !urls.isEmpty, !isImporting else { return }
        isImporting = true
        let folder = folderURL
        Task {
            for url in urls {
                do {
                    let imported = try await Task.detached(priority: .userInitiated) {
                        try MediaFileImporter.importFile(from: url, projectFolder: folder)
                    }.value
                    switch imported.asset.kind {
                    case .image:
                        addImageLayer(for: imported.asset)
                    case .video:
                        addVideoLayer(for: imported.asset, duration: imported.duration, pixelSize: imported.pixelSize)
                    case .audio:
                        addAudioLayer(for: imported.asset, duration: imported.duration)
                    case .font:
                        addAssetOnly(imported.asset)
                    }
                } catch {
                    lastError = "Could not import \(url.lastPathComponent): \(error.localizedDescription)"
                }
                if url.lastPathComponent.hasPrefix("MotionStudio-Photos-") {
                    try? FileManager.default.removeItem(at: url)
                }
            }
            isImporting = false
        }
    }

    private func addVideoLayer(for asset: Asset, duration: Double, pixelSize: Vec2?) {
        let comp = composition
        let sourceSize = pixelSize ?? Vec2(x: Double(comp.width), y: Double(comp.height))
        let size = ImageLayerFactory.fittedSize(pixelSize: sourceSize, in: comp) ?? comp.center
        let length = min(max(duration.isFinite && duration > 0 ? duration : comp.duration.seconds, 1.0 / comp.frameRate.framesPerSecond), comp.duration.seconds)
        let layer = Layer(name: (asset.displayName as NSString).deletingPathExtension,
                          kind: .video(assetID: asset.id), size: size,
                          fill: RGBA(r: 0.15, g: 0.15, b: 0.15),
                          inPoint: .zero, outPoint: Time(seconds: length), position: comp.center)
        run(AddMediaLayer(compositionID: compositionID, asset: asset, layer: layer, index: 0))
        if composition.layer(withID: layer.id) != nil { selectedLayerID = layer.id }
    }

    private func addAudioLayer(for asset: Asset, duration: Double, startTime: Time = .zero) {
        let comp = composition
        let start = min(max(startTime.seconds, 0), max(0, comp.duration.seconds - 1.0 / comp.frameRate.framesPerSecond))
        let available = max(1.0 / comp.frameRate.framesPerSecond, comp.duration.seconds - start)
        let length = min(max(duration.isFinite && duration > 0 ? duration : 1, 1.0 / comp.frameRate.framesPerSecond), available)
        let layer = Layer(name: (asset.displayName as NSString).deletingPathExtension,
                          kind: .audio(assetID: asset.id), size: Vec2(x: Double(comp.width), y: 1),
                          fill: RGBA(r: 0.25, g: 0.72, b: 0.55),
                          inPoint: Time(seconds: start), outPoint: Time(seconds: start + length), position: comp.center)
        run(AddMediaLayer(compositionID: compositionID, asset: asset, layer: layer, index: 0))
        if composition.layer(withID: layer.id) != nil { selectedLayerID = layer.id }
    }

    private func addAssetOnly(_ asset: Asset) {
        run(AddProjectAsset(asset: asset))
        if asset.kind == .font, let url = ProjectMedia.fileURL(for: asset, inProjectFolder: folderURL) {
            customFontNames = Array(Set(customFontNames + FontRegistrar.register(url: url))).sorted()
        }
    }

    func setTextFont(_ layerID: UUID, to fontName: String?) {
        run(SetLayerTextFont(compositionID: compositionID, layerID: layerID, fontName: fontName))
    }

    func setText(_ layerID: UUID, to text: String) {
        run(SetLayerText(compositionID: compositionID, layerID: layerID, text: text))
    }

    func extractAudio(fromVideoLayerID layerID: UUID) {
        guard let layer = composition.layer(withID: layerID),
              case .video(let assetID) = layer.kind,
              let asset = project.assets.first(where: { $0.id == assetID }),
              let url = ProjectMedia.fileURL(for: asset, inProjectFolder: folderURL) else { return }
        guard !isImporting else { return }
        isImporting = true
        let folder = folderURL
        Task {
            do {
                let extracted = try await AudioExtractor.extract(from: url, projectFolder: folder)
                addAudioLayer(for: extracted.asset, duration: extracted.duration, startTime: layer.inPoint)
            } catch {
                lastError = "Audio extraction failed: \(error.localizedDescription)"
            }
            isImporting = false
        }
    }

    /// Trims a layer to a frame-aligned interval. Repeated drag updates become one undo step.
    func setLayerTiming(_ layerID: UUID, inPoint: Time, outPoint: Time, coalescing: Bool) {
        let key = coalescing ? "trim-\(layerID.uuidString)" : nil
        run(SetLayerTiming(compositionID: compositionID, layerID: layerID,
                           inPoint: inPoint, outPoint: outPoint, coalescingKey: key))
    }

    /// Imports picture data, for example from the Photos library.
    func importImage(data: Data, fileExtension: String, baseName: String) {
        beginImport { folder in
            try ImageImporter.importData(data, fileExtension: fileExtension, baseName: baseName, projectFolder: folder)
        }
    }

    private func beginImport(_ work: @escaping @Sendable (URL) throws -> Asset) {
        guard !isImporting else { return }
        isImporting = true
        let folder = folderURL
        Task {
            do {
                // Checking and copying a large picture happens off the main thread.
                let asset = try await Task.detached(priority: .userInitiated) { try work(folder) }.value
                addImageLayer(for: asset)
            } catch {
                lastError = error.localizedDescription
            }
            isImporting = false
        }
    }

    private func addImageLayer(for asset: Asset) {
        guard let layer = ImageLayerFactory.makeLayer(for: asset, in: composition) else {
            ProjectMedia.removeFile(relativePath: asset.relativePath, inProjectFolder: folderURL)
            lastError = "The size of that picture could not be read."
            return
        }
        run(AddMediaLayer(compositionID: compositionID, asset: asset, layer: layer, index: 0))
        if composition.layer(withID: layer.id) != nil {
            selectedLayerID = layer.id
        } else {
            ProjectMedia.removeFile(relativePath: asset.relativePath, inProjectFolder: folderURL)
        }
    }

    // MARK: Effects

    func addEffect(_ effectID: String) {
        guard let layerID = selectedLayerID else { return }
        let instanceID = UUID()
        run(AddEffect(compositionID: compositionID, layerID: layerID, effectID: effectID, instanceID: instanceID))
        if selectedLayer?.effects.contains(where: { $0.id == instanceID }) == true {
            selectedEffectID = instanceID
        }
    }

    func removeEffect(_ instanceID: UUID) {
        guard let layerID = selectedLayerID else { return }
        run(RemoveEffect(compositionID: compositionID, layerID: layerID, instanceID: instanceID))
        if selectedEffectID == instanceID { selectedEffectID = nil }
    }

    /// Moves an effect earlier (negative) or later (positive) in the stack. Order changes the result.
    func moveEffect(_ instanceID: UUID, by offset: Int) {
        guard let layer = selectedLayer, let index = layer.effects.firstIndex(where: { $0.id == instanceID }) else { return }
        let target = index + offset
        guard target >= 0, target < layer.effects.count else { return }
        run(MoveEffect(compositionID: compositionID, layerID: layer.id, instanceID: instanceID, newIndex: target))
    }

    func setEffectEnabled(_ instanceID: UUID, _ isEnabled: Bool) {
        guard let layerID = selectedLayerID else { return }
        run(SetEffectEnabled(compositionID: compositionID, layerID: layerID, instanceID: instanceID, isEnabled: isEnabled))
    }

    /// Changes settings of an effect. While a slider is dragged the changes merge into one undo step.
    func setEffectValues(_ instanceID: UUID, _ values: [String: [Double]], coalescing: Bool) {
        guard let layerID = selectedLayerID else { return }
        let key = coalescing ? "effect-\(instanceID.uuidString)-" + values.keys.sorted().joined(separator: ",") : nil
        run(SetEffectParameters(compositionID: compositionID, layerID: layerID, instanceID: instanceID,
                                values: values, time: currentTime, coalescingKey: key))
    }

    func resetEffect(_ instanceID: UUID) {
        guard let layerID = selectedLayerID else { return }
        run(ResetEffect(compositionID: compositionID, layerID: layerID, instanceID: instanceID))
    }

    // MARK: Keyframes

    /// Selects a keyframe and moves the playhead onto it.
    func selectKeyframe(layerID: UUID, property: PropertyKey, time: Time) {
        selectedLayerID = layerID
        selectedKeyframe = KeyframeRef(layerID: layerID, property: property, time: time)
        if isPlaying { pause() }
        currentFrame = min(max(composition.frameRate.frameIndex(at: time), 0), max(0, frameCount - 1))
    }

    func clearKeyframeSelection() {
        selectedKeyframe = nil
    }

    /// The selected keyframe as stored in the project, if it still exists.
    var selectedKeyframeSnapshot: KeyframeSnapshot? {
        guard let ref = selectedKeyframe, let layer = composition.layer(withID: ref.layerID) else { return nil }
        return layer.keyframeSnapshot(ref.property, at: ref.time)
    }

    /// Moves the selected keyframe to a frame. While dragging, all moves merge into one undo step.
    /// A move onto a frame that already has a keyframe is quietly ignored.
    func moveSelectedKeyframe(toFrame frame: Int64) {
        guard let ref = selectedKeyframe else { return }
        let clamped = min(max(frame, 0), max(0, frameCount - 1))
        let newTime = composition.frameRate.time(ofFrame: clamped)
        guard newTime != ref.time else { return }
        if isPlaying { pause() }
        let command = MoveKeyframe(compositionID: compositionID, layerID: ref.layerID, property: ref.property,
                                   from: ref.time, to: newTime,
                                   coalescingKey: "keyframe-drag-\(ref.layerID.uuidString)-\(ref.property.rawValue)")
        do {
            try document.perform(command)
            // Follow the keyframe before refresh() checks that the selection still exists.
            selectedKeyframe?.time = newTime
            currentFrame = clamped
            refresh()
        } catch {
            // Refused (another keyframe is already there): keep everything as it was.
        }
    }

    func deleteSelectedKeyframe() {
        guard let ref = selectedKeyframe else { return }
        run(RemoveKeyframe(compositionID: compositionID, layerID: ref.layerID,
                           property: ref.property, time: ref.time))
        selectedKeyframe = nil
    }

    func setSelectedKeyframeEasing(_ preset: EasingPreset) {
        guard let ref = selectedKeyframe else { return }
        run(SetKeyframeInterpolation(compositionID: compositionID, layerID: ref.layerID,
                                     property: ref.property, time: ref.time,
                                     interpolation: preset.interpolation))
    }

    /// Applies a user-edited cubic Bezier graph to the selected keyframe's outgoing segment.
    func setSelectedKeyframeCustomEasing(_ ease: BezierEase) {
        guard let ref = selectedKeyframe else { return }
        let safe = BezierEase(min(max(ease.x1, 0), 1), min(max(ease.y1, -1), 2),
                              min(max(ease.x2, 0), 1), min(max(ease.y2, -1), 2))
        run(SetKeyframeInterpolation(compositionID: compositionID, layerID: ref.layerID,
                                     property: ref.property, time: ref.time,
                                     interpolation: .bezier(safe)))
    }

    func copySelectedKeyframe() {
        guard let ref = selectedKeyframe, let snapshot = selectedKeyframeSnapshot else { return }
        copiedKeyframe = (ref.property, snapshot)
    }

    /// Pastes the copied keyframe at the playhead on the selected layer.
    func pasteKeyframe() {
        guard let copied = copiedKeyframe, let layerID = selectedLayerID else { return }
        var snapshot = copied.snapshot
        snapshot.time = currentTime
        run(InsertKeyframe(compositionID: compositionID, layerID: layerID,
                           property: copied.property, snapshot: snapshot))
        selectedKeyframe = KeyframeRef(layerID: layerID, property: copied.property, time: snapshot.time)
    }

    /// Moves the playhead to the previous or next keyframe of the selected layer.
    func jumpToKeyframe(forward: Bool) {
        guard let layer = selectedLayer else { return }
        let now = currentTime
        let target = forward
            ? layer.keyframeTimes.first(where: { $0 > now })
            : layer.keyframeTimes.last(where: { $0 < now })
        if let target { seek(toFrame: composition.frameRate.frameIndex(at: target)) }
    }

    // MARK: Composition settings

    func applyCompositionSettings(width: Int, height: Int, frameRate: FrameRate, durationSeconds: Double) {
        run(SetCompositionSettings(compositionID: compositionID, width: width, height: height,
                                   frameRate: frameRate, durationSeconds: durationSeconds))
    }

    // MARK: Undo and redo

    func undo() {
        if isPlaying { pause() }
        document.undo()
        refresh()
    }

    func redo() {
        if isPlaying { pause() }
        document.redo()
        refresh()
    }

    // MARK: Playhead and playback

    func seek(toFrame frame: Int64) {
        if isPlaying { pause() }
        let last = max(0, frameCount - 1)
        currentFrame = min(max(frame, 0), last)
    }

    func seek(toSeconds seconds: Double) {
        seek(toFrame: composition.frameRate.frameIndex(at: Time(seconds: max(0, seconds))))
    }

    func step(by frames: Int64) {
        seek(toFrame: currentFrame + frames)
    }

    func togglePlayback() {
        if isPlaying { pause() } else { play() }
    }

    func play() {
        guard !isPlaying, frameCount > 1 else { return }
        let startFrame = currentFrame >= frameCount - 1 ? 0 : currentFrame
        currentFrame = startFrame
        clock = PlaybackClock(frameRate: composition.frameRate, frameCount: frameCount,
                              loops: loopPlayback, startFrame: startFrame,
                              startWallTime: CACurrentMediaTime())
        isPlaying = true
        updateAudioPlayback(at: currentTime)
        driver.onTick = { [weak self] wallTime in
            self?.tick(wallTime)
        }
        driver.start()
    }

    func pause() {
        driver.stop()
        isPlaying = false
        clock = nil
        stopAudioPlayback()
    }

    /// Starts audio clips at their timeline-relative offset. Existing players are kept alive during
    /// playback so the display-link does not restart the sound on every frame.
    private func updateAudioPlayback(at time: Time) {
        guard isPlaying else { stopAudioPlayback(); return }
        let active = composition.layers.filter { layer in
            guard layer.isVisible, case .audio = layer.kind else { return false }
            return time >= layer.inPoint && time < layer.outPoint
        }
        let activeIDs = Set(active.map(\.id))
        let stoppedIDs = audioPlayers.keys.filter { !activeIDs.contains($0) }
        for id in stoppedIDs {
            audioPlayers[id]?.stop()
            audioPlayers[id] = nil
        }
        for layer in active { audioPlayers[layer.id]?.volume = Float(layer.audioVolume) }
        for layer in active where audioPlayers[layer.id] == nil {
            guard case .audio(let assetID) = layer.kind,
                  let asset = project.assets.first(where: { $0.id == assetID }),
                  let url = ProjectMedia.fileURL(for: asset, inProjectFolder: folderURL) else { continue }
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
                let player = try AVAudioPlayer(contentsOf: url)
                player.volume = Float(layer.audioVolume)
                player.currentTime = max(0, layer.sourceOffsetSeconds + time.seconds - layer.inPoint.seconds)
                player.prepareToPlay()
                if player.play() { audioPlayers[layer.id] = player }
            } catch {
                lastError = "Audio playback failed for \(layer.name): \(error.localizedDescription)"
            }
        }
    }

    private func stopAudioPlayback() {
        for player in audioPlayers.values { player.stop() }
        audioPlayers.removeAll()
    }

    private func tick(_ wallTime: Double) {
        guard let clock else { return }
        let frame = clock.frame(atWallTime: wallTime)
        // The screen may refresh faster than the composition. Only update when the frame changes.
        if frame != currentFrame {
            currentFrame = frame
            updateAudioPlayback(at: currentTime)
        }
        if clock.hasFinished(atWallTime: wallTime) { pause() }
    }

    // MARK: Saving

    /// Saves immediately. Called when the app goes to the background and when the editor closes.
    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        performSave()
    }

    func shutdown() {
        pause()
        saveNow()
    }

    // MARK: Private

    private func run(_ command: Command) {
        if isPlaying { pause() }
        do {
            try document.perform(command)
            refresh()
        } catch {
            lastError = "That change could not be applied. \(error)"
        }
    }

    private func refresh() {
        project = document.project
        canUndo = document.canUndo
        canRedo = document.canRedo
        undoName = document.undoName
        redoName = document.redoName
        if let id = selectedLayerID, composition.layer(withID: id) == nil {
            selectedLayerID = nil
        }
        if let ref = selectedKeyframe,
           composition.layer(withID: ref.layerID)?.hasKeyframe(ref.property, at: ref.time) != true {
            selectedKeyframe = nil
        }
        if let effectID = selectedEffectID,
           selectedLayer?.effects.contains(where: { $0.id == effectID }) != true {
            selectedEffectID = nil
        }
        invalidatePreviewFrames()
        images.configure(assets: project.assets, folderURL: folderURL)
        let lastFrame = max(0, frameCount - 1)
        if currentFrame > lastFrame { currentFrame = lastFrame }
        scheduleSave()
    }

    private func scheduleSave() {
        saveState = .unsaved
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            self?.performSave()
        }
    }

    private func performSave() {
        do {
            try ProjectFile.save(project, toFolder: folderURL)
            saveState = .saved
        } catch {
            if saveState != .failed {
                lastError = "The project could not be saved. \(error.localizedDescription)"
            }
            saveState = .failed
        }
    }

    private func nextName(_ base: String) -> String {
        let count = composition.layers.filter { $0.name.hasPrefix(base) }.count
        return "\(base) \(count + 1)"
    }
}
