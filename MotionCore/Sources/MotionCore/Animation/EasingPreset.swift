import Foundation

/// Ready-made easing choices. Choosing one simply writes ordinary keyframe easing
/// (a `hold`, `linear` or Bezier curve), which stays fully editable afterwards.
public enum EasingPreset: String, CaseIterable, Identifiable, Sendable {
    case linear
    case hold
    case easeIn
    case easeOut
    case easeInOut
    case strongAcceleration
    case softLanding
    case overshoot

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .linear: return "Linear"
        case .hold: return "Hold"
        case .easeIn: return "Ease in"
        case .easeOut: return "Ease out"
        case .easeInOut: return "Ease in and out"
        case .strongAcceleration: return "Strong acceleration"
        case .softLanding: return "Soft landing"
        case .overshoot: return "Overshoot"
        }
    }

    public var interpolation: Interpolation {
        switch self {
        case .linear: return .linear
        case .hold: return .hold
        case .easeIn: return .bezier(.easeIn)
        case .easeOut: return .bezier(.easeOut)
        case .easeInOut: return .bezier(.easeInOut)
        case .strongAcceleration: return .bezier(BezierEase(0.7, 0, 0.84, 0))
        case .softLanding: return .bezier(BezierEase(0.16, 1, 0.3, 1))
        case .overshoot: return .bezier(BezierEase(0.34, 1.56, 0.64, 1))
        }
    }

    /// The preset that matches an interpolation exactly, or nil for a custom curve.
    public static func matching(_ interpolation: Interpolation) -> EasingPreset? {
        allCases.first(where: { $0.interpolation == interpolation })
    }
}
