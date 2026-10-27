import Foundation

/// Adds an effect to the end of a layer's effect list (or at `index`). Effects run in list order,
/// top to bottom, so the order changes the result.
public struct AddEffect: Command {
    public let compositionID: UUID
    public let layerID: UUID
    public let effectID: String
    public let instanceID: UUID
    public let index: Int?

    public init(compositionID: UUID, layerID: UUID, effectID: String, instanceID: UUID = UUID(), index: Int? = nil) {
        self.compositionID = compositionID
        self.layerID = layerID
        self.effectID = effectID
        self.instanceID = instanceID
        self.index = index
    }

    public var name: String { "Add Effect" }

    public func apply(to project: inout Project) throws {
        try project.updateLayer(compositionID, layerID) { layer in
            guard EffectRegistry.applicabilityMessage(for: layer.kind) == nil else { throw EditError.unsupportedLayerType }
            guard EffectRegistry.isAvailable(id: effectID), var instance = EffectRegistry.makeInstance(id: effectID) else {
                throw EditError.effectUnavailable
            }
            instance.id = instanceID
            let position = index ?? layer.effects.count
            guard position >= 0, position <= layer.effects.count else { throw EditError.indexOutOfRange }
            layer.effects.insert(instance, at: position)
        }
    }
}

public struct RemoveEffect: Command {
    public let compositionID: UUID
    public let layerID: UUID
    public let instanceID: UUID

    public init(compositionID: UUID, layerID: UUID, instanceID: UUID) {
        self.compositionID = compositionID
        self.layerID = layerID
        self.instanceID = instanceID
    }

    public var name: String { "Remove Effect" }

    public func apply(to project: inout Project) throws {
        try project.updateLayer(compositionID, layerID) { layer in
            guard let index = layer.effects.firstIndex(where: { $0.id == instanceID }) else { throw EditError.effectNotFound }
            layer.effects.remove(at: index)
        }
    }
}

public struct MoveEffect: Command {
    public let compositionID: UUID
    public let layerID: UUID
    public let instanceID: UUID
    /// Position in the list after the move (0 runs first).
    public let newIndex: Int

    public init(compositionID: UUID, layerID: UUID, instanceID: UUID, newIndex: Int) {
        self.compositionID = compositionID
        self.layerID = layerID
        self.instanceID = instanceID
        self.newIndex = newIndex
    }

    public var name: String { "Reorder Effects" }

    public func apply(to project: inout Project) throws {
        try project.updateLayer(compositionID, layerID) { layer in
            guard let index = layer.effects.firstIndex(where: { $0.id == instanceID }) else { throw EditError.effectNotFound }
            guard newIndex >= 0, newIndex < layer.effects.count else { throw EditError.indexOutOfRange }
            let effect = layer.effects.remove(at: index)
            layer.effects.insert(effect, at: newIndex)
        }
    }
}

/// Turns an effect on or off without losing its settings.
public struct SetEffectEnabled: Command {
    public let compositionID: UUID
    public let layerID: UUID
    public let instanceID: UUID
    public let isEnabled: Bool

    public init(compositionID: UUID, layerID: UUID, instanceID: UUID, isEnabled: Bool) {
        self.compositionID = compositionID
        self.layerID = layerID
        self.instanceID = instanceID
        self.isEnabled = isEnabled
    }

    public var name: String { isEnabled ? "Enable Effect" : "Disable Effect" }

    public func apply(to project: inout Project) throws {
        try project.updateLayer(compositionID, layerID) { layer in
            guard let index = layer.effects.firstIndex(where: { $0.id == instanceID }) else { throw EditError.effectNotFound }
            layer.effects[index].isEnabled = isEnabled
        }
    }
}

/// Changes one or more settings of an effect in a single undo step. Values are moved into their allowed range.
/// (A colour is three settings, so it uses this command with three entries.)
public struct SetEffectParameters: Command {
    public let compositionID: UUID
    public let layerID: UUID
    public let instanceID: UUID
    /// Setting id to numbers: one number for a scalar or choice, two for a vector.
    public let values: [String: [Double]]
    public let time: Time
    public let coalescingKey: String?

    public init(compositionID: UUID, layerID: UUID, instanceID: UUID, values: [String: [Double]],
                time: Time = .zero, coalescingKey: String? = nil) {
        self.compositionID = compositionID
        self.layerID = layerID
        self.instanceID = instanceID
        self.values = values
        self.time = time
        self.coalescingKey = coalescingKey
    }

    public var name: String { "Change Effect" }

    public func apply(to project: inout Project) throws {
        try project.updateLayer(compositionID, layerID) { layer in
            guard let index = layer.effects.firstIndex(where: { $0.id == instanceID }) else { throw EditError.effectNotFound }
            guard let definition = EffectRegistry.definition(id: layer.effects[index].effectID) else {
                throw EditError.effectUnavailable
            }
            var instance = layer.effects[index]
            for (name, numbers) in values {
                guard let rule = definition.parameters.first(where: { $0.id == name }) else { throw EditError.parameterNotFound }
                try instance.setParameter(rule, to: numbers, at: time)
            }
            layer.effects[index] = instance
        }
    }
}

/// Puts every setting of an effect back to its default.
public struct ResetEffect: Command {
    public let compositionID: UUID
    public let layerID: UUID
    public let instanceID: UUID

    public init(compositionID: UUID, layerID: UUID, instanceID: UUID) {
        self.compositionID = compositionID
        self.layerID = layerID
        self.instanceID = instanceID
    }

    public var name: String { "Reset Effect" }

    public func apply(to project: inout Project) throws {
        try project.updateLayer(compositionID, layerID) { layer in
            guard let index = layer.effects.firstIndex(where: { $0.id == instanceID }) else { throw EditError.effectNotFound }
            guard let fresh = EffectRegistry.makeInstance(id: layer.effects[index].effectID) else {
                throw EditError.effectUnavailable
            }
            layer.effects[index].parameters = fresh.parameters
        }
    }
}
