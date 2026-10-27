import Foundation
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
    /// True while a picture is being checked and copied into the project.
    private(set) var isImporting = false
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

    init(project: Project, folderURL: URL) {
        self.project = project
        self.document = Document(project: project)
        self.folderURL = folderURL
        images.configure(assets: project.assets, folderURL: folderURL)
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
        }
        run(AddLayer(compositionID: compositionID, layer: layer, index: 0))
        selectedLayerID = layer.id
    }

    func deleteSelected() {
        guard let id = selectedLayerID else { return }
        run(RemoveLayer(compositionID: compositionID, layerID: id))
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
        driver.onTick = { [weak self] wallTime in
            self?.tick(wallTime)
        }
        driver.start()
    }

    func pause() {
        driver.stop()
        isPlaying = false
        clock = nil
    }

    private func tick(_ wallTime: Double) {
        guard let clock else { return }
        let frame = clock.frame(atWallTime: wallTime)
        // The screen may refresh faster than the composition. Only update when the frame changes.
        if frame != currentFrame { currentFrame = frame }
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
