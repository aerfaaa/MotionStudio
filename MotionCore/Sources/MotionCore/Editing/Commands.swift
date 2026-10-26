import Foundation

public struct AddLayer: Command {
    public let compositionID: UUID
    public let layer: Layer
    /// 0 puts the layer on top.
    public let index: Int

    public init(compositionID: UUID, layer: Layer, index: Int = 0) {
        self.compositionID = compositionID
        self.layer = layer
        self.index = index
    }

    public var name: String { "Add Layer" }

    public func apply(to project: inout Project) throws {
        try project.updateComposition(compositionID) { composition in
            guard index >= 0, index <= composition.layers.count else { throw EditError.indexOutOfRange }
            guard !composition.layers.contains(where: { $0.id == layer.id }) else { throw EditError.duplicateLayerID }
            composition.layers.insert(layer, at: index)
        }
    }
}

public struct RemoveLayer: Command {
    public let compositionID: UUID
    public let layerID: UUID

    public init(compositionID: UUID, layerID: UUID) {
        self.compositionID = compositionID
        self.layerID = layerID
    }

    public var name: String { "Delete Layer" }

    public func apply(to project: inout Project) throws {
        try project.updateComposition(compositionID) { composition in
            guard let index = composition.index(ofLayer: layerID) else { throw EditError.layerNotFound }
            composition.layers.remove(at: index)
            // Layers that followed the deleted layer become independent.
            for i in composition.layers.indices where composition.layers[i].parentID == layerID {
                composition.layers[i].parentID = nil
            }
        }
    }
}

public struct ReorderLayer: Command {
    public let compositionID: UUID
    public let layerID: UUID
    /// The layer's index after the move (0 = top).
    public let newIndex: Int

    public init(compositionID: UUID, layerID: UUID, newIndex: Int) {
        self.compositionID = compositionID
        self.layerID = layerID
        self.newIndex = newIndex
    }

    public var name: String { "Reorder Layer" }

    public func apply(to project: inout Project) throws {
        try project.updateComposition(compositionID) { composition in
            guard let index = composition.index(ofLayer: layerID) else { throw EditError.layerNotFound }
            guard newIndex >= 0, newIndex < composition.layers.count else { throw EditError.indexOutOfRange }
            let layer = composition.layers.remove(at: index)
            composition.layers.insert(layer, at: newIndex)
        }
    }
}

public struct RenameLayer: Command {
    public let compositionID: UUID
    public let layerID: UUID
    public let newName: String

    public init(compositionID: UUID, layerID: UUID, newName: String) {
        self.compositionID = compositionID
        self.layerID = layerID
        self.newName = newName
    }

    public var name: String { "Rename Layer" }

    public func apply(to project: inout Project) throws {
        try project.updateLayer(compositionID, layerID) { layer in
            layer.name = newName
        }
    }
}

public struct SetLayerVisibility: Command {
    public let compositionID: UUID
    public let layerID: UUID
    public let isVisible: Bool

    public init(compositionID: UUID, layerID: UUID, isVisible: Bool) {
        self.compositionID = compositionID
        self.layerID = layerID
        self.isVisible = isVisible
    }

    public var name: String { isVisible ? "Show Layer" : "Hide Layer" }

    public func apply(to project: inout Project) throws {
        try project.updateLayer(compositionID, layerID) { layer in
            layer.isVisible = isVisible
        }
    }
}

public struct SetLayerFill: Command {
    public let compositionID: UUID
    public let layerID: UUID
    public let fill: RGBA

    public init(compositionID: UUID, layerID: UUID, fill: RGBA) {
        self.compositionID = compositionID
        self.layerID = layerID
        self.fill = fill
    }

    public var name: String { "Change Colour" }

    public func apply(to project: inout Project) throws {
        try project.updateLayer(compositionID, layerID) { layer in
            layer.fill = fill
        }
    }
}

public struct SetLayerTiming: Command {
    public let compositionID: UUID
    public let layerID: UUID
    public let inPoint: Time
    public let outPoint: Time

    public init(compositionID: UUID, layerID: UUID, inPoint: Time, outPoint: Time) {
        self.compositionID = compositionID
        self.layerID = layerID
        self.inPoint = inPoint
        self.outPoint = outPoint
    }

    public var name: String { "Change Layer Timing" }

    public func apply(to project: inout Project) throws {
        guard outPoint > inPoint else { throw EditError.invalidTiming }
        try project.updateLayer(compositionID, layerID) { layer in
            layer.inPoint = inPoint
            layer.outPoint = outPoint
        }
    }
}

/// Changes a two-number property (position, scale, anchor). If the property has keyframes the
/// edit becomes a keyframe at `time`; otherwise it changes the fixed value.
public struct SetVectorProperty: Command {
    public let compositionID: UUID
    public let layerID: UUID
    public let property: PropertyKey
    public let time: Time
    public let value: Vec2
    public let coalescingKey: String?

    public init(compositionID: UUID, layerID: UUID, property: PropertyKey,
                time: Time, value: Vec2, coalescingKey: String? = nil) {
        self.compositionID = compositionID
        self.layerID = layerID
        self.property = property
        self.time = time
        self.value = value
        self.coalescingKey = coalescingKey
    }

    public var name: String {
        property == .position ? "Move Layer" : "Change \(property.displayName)"
    }

    public func apply(to project: inout Project) throws {
        try project.updateLayer(compositionID, layerID) { layer in
            try layer.setVector(property, to: value, at: time)
        }
    }
}

/// Changes a one-number property (rotation, opacity). Works like `SetVectorProperty`.
public struct SetScalarProperty: Command {
    public let compositionID: UUID
    public let layerID: UUID
    public let property: PropertyKey
    public let time: Time
    public let value: Double
    public let coalescingKey: String?

    public init(compositionID: UUID, layerID: UUID, property: PropertyKey,
                time: Time, value: Double, coalescingKey: String? = nil) {
        self.compositionID = compositionID
        self.layerID = layerID
        self.property = property
        self.time = time
        self.value = value
        self.coalescingKey = coalescingKey
    }

    public var name: String { "Change \(property.displayName)" }

    public func apply(to project: inout Project) throws {
        try project.updateLayer(compositionID, layerID) { layer in
            try layer.setScalar(property, to: value, at: time)
        }
    }
}

public struct AddKeyframe: Command {
    public let compositionID: UUID
    public let layerID: UUID
    public let property: PropertyKey
    public let time: Time

    public init(compositionID: UUID, layerID: UUID, property: PropertyKey, time: Time) {
        self.compositionID = compositionID
        self.layerID = layerID
        self.property = property
        self.time = time
    }

    public var name: String { "Add Keyframe" }

    public func apply(to project: inout Project) throws {
        try project.updateLayer(compositionID, layerID) { layer in
            try layer.addKeyframe(property, at: time)
        }
    }
}

public struct RemoveKeyframe: Command {
    public let compositionID: UUID
    public let layerID: UUID
    public let property: PropertyKey
    public let time: Time

    public init(compositionID: UUID, layerID: UUID, property: PropertyKey, time: Time) {
        self.compositionID = compositionID
        self.layerID = layerID
        self.property = property
        self.time = time
    }

    public var name: String { "Remove Keyframe" }

    public func apply(to project: inout Project) throws {
        try project.updateLayer(compositionID, layerID) { layer in
            try layer.removeKeyframe(property, at: time)
        }
    }
}

/// Moves a keyframe to another time. While a finger drags a keyframe, the moves merge into one undo step.
public struct MoveKeyframe: Command {
    public let compositionID: UUID
    public let layerID: UUID
    public let property: PropertyKey
    public let from: Time
    public let to: Time
    public let coalescingKey: String?

    public init(compositionID: UUID, layerID: UUID, property: PropertyKey,
                from: Time, to: Time, coalescingKey: String? = nil) {
        self.compositionID = compositionID
        self.layerID = layerID
        self.property = property
        self.from = from
        self.to = to
        self.coalescingKey = coalescingKey
    }

    public var name: String { "Move Keyframe" }

    public func apply(to project: inout Project) throws {
        try project.updateLayer(compositionID, layerID) { layer in
            try layer.moveKeyframe(property, from: from, to: to)
        }
    }
}

public struct SetKeyframeInterpolation: Command {
    public let compositionID: UUID
    public let layerID: UUID
    public let property: PropertyKey
    public let time: Time
    public let interpolation: Interpolation

    public init(compositionID: UUID, layerID: UUID, property: PropertyKey,
                time: Time, interpolation: Interpolation) {
        self.compositionID = compositionID
        self.layerID = layerID
        self.property = property
        self.time = time
        self.interpolation = interpolation
    }

    public var name: String { "Change Easing" }

    public func apply(to project: inout Project) throws {
        try project.updateLayer(compositionID, layerID) { layer in
            try layer.setKeyframeInterpolation(property, at: time, to: interpolation)
        }
    }
}

/// Adds a keyframe with a given value (used for paste).
public struct InsertKeyframe: Command {
    public let compositionID: UUID
    public let layerID: UUID
    public let property: PropertyKey
    public let snapshot: KeyframeSnapshot
    public let commandName: String

    public init(compositionID: UUID, layerID: UUID, property: PropertyKey,
                snapshot: KeyframeSnapshot, commandName: String = "Paste Keyframe") {
        self.compositionID = compositionID
        self.layerID = layerID
        self.property = property
        self.snapshot = snapshot
        self.commandName = commandName
    }

    public var name: String { commandName }

    public func apply(to project: inout Project) throws {
        try project.updateLayer(compositionID, layerID) { layer in
            try layer.insertKeyframe(property, snapshot)
        }
    }
}

/// Changes a composition's size, frame rate or length.
///
/// - Layers keep their pixel positions and sizes, so artwork is never stretched when the canvas changes.
/// - A new length is always a whole number of frames. Layers that ended exactly at the old end follow the new end.
public struct SetCompositionSettings: Command {
    public static let minimumSize = 16
    public static let maximumSize = 16384

    public let compositionID: UUID
    public let width: Int
    public let height: Int
    public let frameRate: FrameRate
    public let durationSeconds: Double

    public init(compositionID: UUID, width: Int, height: Int, frameRate: FrameRate, durationSeconds: Double) {
        self.compositionID = compositionID
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.durationSeconds = durationSeconds
    }

    public var name: String { "Composition Settings" }

    public func apply(to project: inout Project) throws {
        guard width >= SetCompositionSettings.minimumSize, width <= SetCompositionSettings.maximumSize,
              height >= SetCompositionSettings.minimumSize, height <= SetCompositionSettings.maximumSize,
              durationSeconds > 0, Time(seconds: durationSeconds) <= Time.maximumDuration else {
            throw EditError.invalidValue
        }
        try project.updateComposition(compositionID) { composition in
            let oldDuration = composition.duration
            let newDuration = Composition.wholeFrameDuration(seconds: durationSeconds, frameRate: frameRate)
            composition.width = width
            composition.height = height
            composition.frameRate = frameRate
            composition.duration = newDuration
            for index in composition.layers.indices where composition.layers[index].outPoint == oldDuration {
                composition.layers[index].outPoint = newDuration
            }
        }
    }
}
