import Foundation

/// How a layer's colours combine with what is underneath it.
/// V1 draws all four. More modes can be added later without changing saved files.
public enum BlendMode: String, Codable, CaseIterable, Sendable {
    case normal
    case add
    case multiply
    case screen
}
