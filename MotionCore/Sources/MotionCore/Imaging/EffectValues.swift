import Foundation

/// The settings of one effect, ready to use: every setting exists, is a real number and is inside its allowed range.
///
/// Missing, damaged or out-of-range settings (for example from an old or edited project file) are replaced
/// by the effect's default or moved into range, so a processor never has to check for bad input.
public struct EffectValues: Equatable {
    private let numbers: [String: [Double]]

    public init(values: [String: [Double]], definition: EffectDefinition?) {
        var result: [String: [Double]] = [:]
        for rule in definition?.parameters ?? [] {
            let given = values[rule.id]
            switch rule.kind {
            case .scalar(_, _, let defaultValue):
                if let given, given.count == 1, given[0].isFinite {
                    result[rule.id] = [EffectRegistry.clamp(given[0], for: rule.kind)]
                } else {
                    result[rule.id] = [defaultValue]
                }
            case .choice(_, let defaultIndex):
                if let given, given.count == 1, given[0].isFinite {
                    result[rule.id] = [EffectRegistry.clamp(given[0], for: rule.kind)]
                } else {
                    result[rule.id] = [Double(defaultIndex)]
                }
            case .vector(let defaultValue):
                if let given, given.count == 2, given[0].isFinite, given[1].isFinite {
                    result[rule.id] = [min(max(given[0], -10_000), 10_000), min(max(given[1], -10_000), 10_000)]
                } else {
                    result[rule.id] = [defaultValue.x, defaultValue.y]
                }
            }
        }
        self.numbers = result
    }

    public init(resolved: ResolvedEffect) {
        self.init(values: resolved.values, definition: EffectRegistry.definition(id: resolved.effectID))
    }

    public func scalar(_ id: String) -> Double { numbers[id]?.first ?? 0 }

    public func vector(_ id: String) -> Vec2 {
        guard let pair = numbers[id], pair.count == 2 else { return .zero }
        return Vec2(x: pair[0], y: pair[1])
    }

    public func choice(_ id: String) -> Int { Int((numbers[id]?.first ?? 0).rounded()) }

    /// A colour stored as three settings named `<prefix>Red`, `<prefix>Green` and `<prefix>Blue`.
    public func color(_ prefix: String) -> (Float, Float, Float) {
        (Float(scalar(prefix + "Red")), Float(scalar(prefix + "Green")), Float(scalar(prefix + "Blue")))
    }
}
