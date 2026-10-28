import Foundation

/// The animatable transform properties every layer has.
public enum PropertyKey: String, Codable, CaseIterable, Sendable {
    case position
    case scale
    case anchor
    case rotation
    case opacity

    /// Position, scale and anchor hold two numbers (x and y). Rotation and opacity hold one.
    public var isVector: Bool {
        switch self {
        case .position, .scale, .anchor: return true
        case .rotation, .opacity: return false
        }
    }

    public var displayName: String {
        switch self {
        case .position: return "Position"
        case .scale: return "Scale"
        case .anchor: return "Anchor point"
        case .rotation: return "Rotation"
        case .opacity: return "Opacity"
        }
    }
}
