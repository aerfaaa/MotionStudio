import Foundation

public enum AssetKind: String, Codable, Sendable {
    case image
    case video
    case audio
    case font
}

/// A media file used by the project. Files live inside the project folder, and the
/// project only remembers the relative path. (V1 does not import media yet.)
public struct Asset: Codable, Equatable, Identifiable {
    public var id: UUID
    public var kind: AssetKind
    public var displayName: String
    /// Path inside the project folder, for example "media/photo.jpg".
    public var relativePath: String

    public init(id: UUID = UUID(), kind: AssetKind, displayName: String, relativePath: String) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.relativePath = relativePath
    }
}
