import Foundation

/// The project plus its undo and redo history.
///
/// Undo works by remembering a copy of the whole project from before each edit. Swift copies
/// value types lazily, and a project holds settings and keyframes (not video), so this is cheap
/// and very hard to get wrong. If projects ever grow huge, this can be replaced behind the same API.
public final class Document {
    private struct Entry {
        var name: String
        var snapshot: Project
        var coalescingKey: String?
    }

    public private(set) var project: Project
    /// Goes up by one on every change, including undo and redo.
    public private(set) var revision: Int = 0
    public var maxUndoSteps: Int

    private var undoStack: [Entry] = []
    private var redoStack: [Entry] = []

    public init(project: Project, maxUndoSteps: Int = 200) {
        self.project = project
        self.maxUndoSteps = maxUndoSteps
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    public var undoName: String? { undoStack.last?.name }
    public var redoName: String? { redoStack.last?.name }

    /// Applies an edit. If it throws, nothing changes. An edit that changes nothing is not recorded.
    public func perform(_ command: Command) throws {
        var updated = project
        try command.apply(to: &updated)
        guard updated != project else { return }

        if let key = command.coalescingKey, let last = undoStack.last, last.coalescingKey == key {
            // Same drag as the previous edit: keep the older "before" copy, so one undo reverses it all.
        } else {
            undoStack.append(Entry(name: command.name, snapshot: project, coalescingKey: command.coalescingKey))
            if undoStack.count > maxUndoSteps {
                undoStack.removeFirst(undoStack.count - maxUndoSteps)
            }
        }
        project = updated
        redoStack.removeAll()
        revision += 1
    }

    /// Call when a drag ends, so the next drag becomes a separate undo step.
    public func endGroup() {
        guard !undoStack.isEmpty else { return }
        undoStack[undoStack.count - 1].coalescingKey = nil
    }

    @discardableResult
    public func undo() -> Bool {
        guard let entry = undoStack.popLast() else { return false }
        redoStack.append(Entry(name: entry.name, snapshot: project, coalescingKey: nil))
        project = entry.snapshot
        revision += 1
        return true
    }

    @discardableResult
    public func redo() -> Bool {
        guard let entry = redoStack.popLast() else { return false }
        undoStack.append(Entry(name: entry.name, snapshot: project, coalescingKey: nil))
        project = entry.snapshot
        revision += 1
        return true
    }
}
