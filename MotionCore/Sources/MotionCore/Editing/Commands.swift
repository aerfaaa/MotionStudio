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
