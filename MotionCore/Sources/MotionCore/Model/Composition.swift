import Foundation

/// A canvas with a fixed pixel size, frame rate and length, holding layers.
///
/// The frame rate belongs to the composition. It has nothing to do with how fast
/// the screen refreshes: a 24 fps composition plays at 24 fps on a 120 Hz display.
public struct Composition: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    /// Size in pixels. Independent of any device screen.
    public var width: Int
    public var height: Int
    public var frameRate: FrameRate
    public var duration: Time
    public var background: RGBA
    /// Index 0 is the TOP layer (drawn last), like the layer stack in After Effects.
    public var layers: [Layer]

    public init(id: UUID = UUID(),
                name: String,
                width: Int,
                height: Int,
                frameRate: FrameRate,
                duration: Time,
                background: RGBA = RGBA(r: 0.06, g: 0.06, b: 0.07),
                layers: [Layer] = []) {
        self.id = id
        self.name = name
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.duration = duration
        self.background = background
        self.layers = layers
    }

    /// Number of frames in the composition. The last frame is `frameCount - 1`.
    public var frameCount: Int64 {
        frameRate.frameCount(for: duration)
    }

    public var center: Vec2 {
        Vec2(x: Double(width) / 2, y: Double(height) / 2)
    }

    /// A length that is a whole number of frames, rounded to the nearest frame
    /// (5 seconds at 29.97 fps is 150 frames, which is 5.005 seconds).
    public static func wholeFrameDuration(seconds: Double, frameRate: FrameRate) -> Time {
        let frames = max(1, Int64((seconds * frameRate.framesPerSecond).rounded()))
        return frameRate.time(ofFrame: frames)
    }

    public func layer(withID id: UUID) -> Layer? {
        layers.first(where: { $0.id == id })
    }

    public func index(ofLayer id: UUID) -> Int? {
        layers.firstIndex(where: { $0.id == id })
    }
}
