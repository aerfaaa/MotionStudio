import Foundation

/// One adjustable setting of an effect. Settings can be animated like any layer property.
public enum EffectParameter: Codable, Equatable {
    case scalar(AnimatedProperty<Double>)
    case vector(AnimatedProperty<Vec2>)
}

/// An effect applied to a layer, for example a blur.
///
/// V1 stores and evaluates these but ships no effects and draws none. This type exists now
/// so that saved projects, the evaluator and the undo system already have a place for effects.
/// `effectID` names a built-in effect (for example "blur.gaussian") that a renderer looks up.
public struct EffectInstance: Codable, Equatable, Identifiable {
    public var id: UUID
    public var effectID: String
    public var isEnabled: Bool
    public var parameters: [String: EffectParameter]

    public init(id: UUID = UUID(), effectID: String, isEnabled: Bool = true,
                parameters: [String: EffectParameter] = [:]) {
        self.id = id
        self.effectID = effectID
        self.isEnabled = isEnabled
        self.parameters = parameters
    }
}
