import Foundation
import MotionCore
import Observation
import QuartzCore

enum SaveState: Equatable {
    case saved
    case unsaved
    case failed
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
        selectedLayerID = id
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
