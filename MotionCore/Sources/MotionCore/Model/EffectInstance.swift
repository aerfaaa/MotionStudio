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

extension EffectInstance {
    /// Sets one setting from numbers (one for a scalar or choice, two for a vector). The value is moved into
    /// the allowed range. If the setting already has keyframes the edit becomes a keyframe at `time`;
    /// otherwise it changes the fixed value.
    public mutating func setParameter(_ rule: EffectParameterDefinition, to numbers: [Double], at time: Time) throws {
        switch rule.kind {
        case .scalar, .choice:
            guard numbers.count == 1, numbers[0].isFinite else { throw EditError.invalidValue }
            let value = EffectRegistry.clamp(numbers[0], for: rule.kind)
            var track: AnimatedProperty<Double>
            if case .scalar(let existing)? = parameters[rule.id] {
                track = existing
            } else {
                track = AnimatedProperty(value)
            }
            if track.isAnimated {
                let easing = track.keyframe(at: time)?.outgoing ?? .linear
                track.setKeyframe(at: time, value: value, interpolation: easing)
            } else {
                track.staticValue = value
            }
            parameters[rule.id] = .scalar(track)
        case .vector:
            guard numbers.count == 2, numbers[0].isFinite, numbers[1].isFinite else { throw EditError.invalidValue }
            let value = Vec2(x: min(max(numbers[0], -10_000), 10_000), y: min(max(numbers[1], -10_000), 10_000))
            var track: AnimatedProperty<Vec2>
            if case .vector(let existing)? = parameters[rule.id] {
                track = existing
            } else {
                track = AnimatedProperty(value)
            }
            if track.isAnimated {
                let easing = track.keyframe(at: time)?.outgoing ?? .linear
                track.setKeyframe(at: time, value: value, interpolation: easing)
            } else {
                track.staticValue = value
            }
            parameters[rule.id] = .vector(track)
        }
    }
}
