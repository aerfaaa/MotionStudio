import Foundation

/// How far an effect has got. Honest labels only:
/// - `missing`: listed in the catalogue, nothing is drawn yet
/// - `partial`: draws something real but not everything it should
/// - `working`: implemented and checked by tests
public enum EffectStatus: String, Codable, CaseIterable, Sendable {
    case missing
    case partial
    case working

    public var displayName: String {
        switch self {
        case .missing: return "Missing"
        case .partial: return "Partial"
        case .working: return "Working"
        }
    }
}

public enum EffectCategory: String, CaseIterable, Sendable {
    case blurSharpen
    case light
    case color
    case distort
    case generate
    case stylize
    case keyingMatte
    case repeatTile
    case transition
    case animation
    case text
    case threeD

    public var displayName: String {
        switch self {
        case .blurSharpen: return "Blur and sharpen"
        case .light: return "Glow, light and shadow"
        case .color: return "Colour"
        case .distort: return "Distort"
        case .generate: return "Generate"
        case .stylize: return "Stylize"
        case .keyingMatte: return "Keying and mattes"
        case .repeatTile: return "Repeat and tile"
        case .transition: return "Transitions"
        case .animation: return "Animation and time"
        case .text: return "Text"
        case .threeD: return "3D and 360"
        }
    }
}

/// The kind of value one effect setting holds.
public enum EffectParameterKind: Equatable, Sendable {
    case scalar(min: Double, max: Double, defaultValue: Double)
    case vector(defaultValue: Vec2)
    /// A pick from a list. Stored as the number of the chosen option.
    case choice(options: [String], defaultIndex: Int)
}

public struct EffectParameterDefinition: Equatable, Sendable {
    public let id: String
    public let name: String
    public let kind: EffectParameterKind

    public init(id: String, name: String, kind: EffectParameterKind) {
        self.id = id
        self.name = name
        self.kind = kind
    }
}

public struct EffectDefinition: Identifiable, Equatable, Sendable {
    public let id: String
    /// The exact display name from the product specification.
    public let name: String
    public let category: EffectCategory
    public let status: EffectStatus
    public let parameters: [EffectParameterDefinition]

    public init(id: String, name: String, category: EffectCategory,
                status: EffectStatus, parameters: [EffectParameterDefinition]) {
        self.id = id
        self.name = name
        self.category = category
        self.status = status
        self.parameters = parameters
    }
}
