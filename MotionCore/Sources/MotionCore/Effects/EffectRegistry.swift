import Foundation

/// The list of every effect Motion Studio knows about, and the rules for their settings.
///
/// Listing an effect here does NOT mean it draws anything. Check `status`: connected pixel
/// processors are `partial`, and catalogue entries without a processor are `missing`.
public enum EffectRegistry {

    /// Every effect: the required catalogue plus the extra entries. An effect is `partial` once real
    /// processing code is connected (`ImageEffects`), otherwise `missing`. None is `working` until its
    /// tests have actually been run and passed.
    public static let all: [EffectDefinition] = (EffectCatalogData.entries + EffectCatalogData.additionalEntries).map { entry in
        let id = slug(entry.name)
        return EffectDefinition(id: id, name: entry.name, category: entry.category,
                                status: ImageEffects.isAvailable(id) ? .partial : .missing,
                                parameters: EffectParameterTable.parameters[id] ?? [])
    }

    /// Effects that can really be applied now (their processing code is connected), in catalogue order
    /// within each category.
    public static var available: [EffectDefinition] {
        all.filter { ImageEffects.isAvailable($0.id) }
    }

    public static func isAvailable(id: String) -> Bool {
        ImageEffects.isAvailable(id)
    }

    /// nil if effects can be applied to this kind of layer, otherwise a message for the user.
    /// Vector layers are rasterized by the app renderer before the same pixel effect pipeline is used.
    public static func applicabilityMessage(for kind: LayerKind) -> String? {
        switch kind {
        case .image, .video, .solid, .shape, .text, .adjustment, .vectorPath:
            return nil
        case .audio:
            return "Audio clips do not have visual effects."
        case .null:
            return "A null layer has no picture to apply effects to."
        }
    }

    private static let byID: [String: EffectDefinition] =
        Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    public static func definition(id: String) -> EffectDefinition? {
        byID[id]
    }

    public static func definitions(in category: EffectCategory) -> [EffectDefinition] {
        all.filter { $0.category == category }
    }

    /// Case-insensitive search by name.
    public static func search(_ text: String) -> [EffectDefinition] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return all }
        return all.filter { $0.name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    /// A stable id made from the name: lower case letters and digits separated by single dashes.
    /// "Channel Remap (HSV)" becomes "channel-remap-hsv".
    public static func slug(_ name: String) -> String {
        var result = ""
        var lastWasDash = true
        for scalar in name.lowercased().unicodeScalars {
            let isLetter = scalar.value >= 97 && scalar.value <= 122
            let isDigit = scalar.value >= 48 && scalar.value <= 57
            if isLetter || isDigit {
                result.unicodeScalars.append(scalar)
                lastWasDash = false
            } else if !lastWasDash {
                result.append("-")
                lastWasDash = true
            }
        }
        while result.hasSuffix("-") { result.removeLast() }
        return result
    }

    /// A new effect with every setting at its default.
    public static func makeInstance(id: String) -> EffectInstance? {
        guard let definition = definition(id: id) else { return nil }
        var parameters: [String: EffectParameter] = [:]
        for parameter in definition.parameters {
            switch parameter.kind {
            case .scalar(_, _, let defaultValue):
                parameters[parameter.id] = .scalar(AnimatedProperty(defaultValue))
            case .vector(let defaultValue):
                parameters[parameter.id] = .vector(AnimatedProperty(defaultValue))
            case .choice(_, let defaultIndex):
                parameters[parameter.id] = .scalar(AnimatedProperty(Double(defaultIndex)))
            }
        }
        return EffectInstance(effectID: id, parameters: parameters)
    }

    /// Keeps a number inside the range its setting allows.
    public static func clamp(_ value: Double, for kind: EffectParameterKind) -> Double {
        switch kind {
        case .scalar(let minimum, let maximum, _):
            return min(max(value, minimum), maximum)
        case .choice(let options, _):
            let last = Double(max(options.count - 1, 0))
            return min(max(value.rounded(), 0), last)
        case .vector:
            return value
        }
    }

    /// Describes everything wrong with an effect's settings. An empty list means it is valid.
    public static func problems(in instance: EffectInstance) -> [String] {
        guard let definition = definition(id: instance.effectID) else {
            return ["Unknown effect \"\(instance.effectID)\"."]
        }
        var found: [String] = []
        for (name, parameter) in instance.parameters.sorted(by: { $0.key < $1.key }) {
            guard let rule = definition.parameters.first(where: { $0.id == name }) else {
                found.append("\"\(name)\" is not a setting of \(definition.name).")
                continue
            }
            switch (parameter, rule.kind) {
            case (.scalar(let track), .scalar), (.scalar(let track), .choice):
                let values = [track.staticValue] + track.keyframes.map { $0.value }
                for value in values where clamp(value, for: rule.kind) != value {
                    found.append("\(rule.name) of \(definition.name) is outside its allowed range.")
                    break
                }
            case (.vector, .vector):
                break
            default:
                found.append("\(rule.name) of \(definition.name) holds the wrong kind of value.")
            }
        }
        return found
    }

    /// A copy with every out-of-range number moved back inside its allowed range.
    /// Unknown settings and settings of the wrong kind are dropped.
    public static func repaired(_ instance: EffectInstance) -> EffectInstance {
        guard let definition = definition(id: instance.effectID) else { return instance }
        var result = instance
        result.parameters = [:]
        for (name, parameter) in instance.parameters {
            guard let rule = definition.parameters.first(where: { $0.id == name }) else { continue }
            switch (parameter, rule.kind) {
            case (.scalar(let track), .scalar), (.scalar(let track), .choice):
                let keyframes = track.keyframes.map {
                    Keyframe(time: $0.time, value: clamp($0.value, for: rule.kind), outgoing: $0.outgoing)
                }
                result.parameters[name] = .scalar(AnimatedProperty(clamp(track.staticValue, for: rule.kind),
                                                                    keyframes: keyframes))
            case (.vector, .vector):
                result.parameters[name] = parameter
            default:
                break
            }
        }
        return result
    }
}
