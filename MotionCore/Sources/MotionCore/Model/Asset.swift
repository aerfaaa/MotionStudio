import Foundation

public enum AssetKind: String, Codable, Sendable {
    case image
    case video
    case audio
    case font
}

/// A media file used by the project. The file lives inside the project folder (in `media/`), and the
/// project only remembers its relative path. Only images can be imported at the moment; the other kinds
/// are reserved so video, audio and fonts can be added later without changing the saved format.
public struct Asset: Codable, Equatable, Identifiable {
    public var id: UUID
    public var kind: AssetKind
    public var displayName: String
    /// Path inside the project folder, for example "media/3F2A-photo.jpg".
    public var relativePath: String
    /// Width and height in pixels for images (after applying the photo's rotation). Nil if unknown.
    public var pixelSize: Vec2?

    public init(id: UUID = UUID(), kind: AssetKind, displayName: String, relativePath: String,
                pixelSize: Vec2? = nil) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.relativePath = relativePath
        self.pixelSize = pixelSize
    }

    // Projects saved before pixel sizes existed have no "pixelSize" key; that must keep working.
    private enum CodingKeys: String, CodingKey {
        case id, kind, displayName, relativePath, pixelSize
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(AssetKind.self, forKey: .kind)
        displayName = try c.decode(String.self, forKey: .displayName)
        relativePath = try c.decode(String.self, forKey: .relativePath)
        pixelSize = try c.decodeIfPresent(Vec2.self, forKey: .pixelSize)
    }
}
