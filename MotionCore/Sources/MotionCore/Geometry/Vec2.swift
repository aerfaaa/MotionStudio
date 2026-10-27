import Foundation

/// A point or size in two dimensions. In a composition, (0, 0) is the top-left corner
/// and y grows downward, in composition PIXELS (never screen points).
public struct Vec2: Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Vec2(x: 0, y: 0)
    public static let one = Vec2(x: 1, y: 1)

    public static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(x: a.x + b.x, y: a.y + b.y) }
    public static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(x: a.x - b.x, y: a.y - b.y) }
    public static func * (a: Vec2, k: Double) -> Vec2 { Vec2(x: a.x * k, y: a.y * k) }

    public var length: Double { (x * x + y * y).squareRoot() }
}

/// A colour in the sRGB colour space, each channel from 0 to 1.
public struct RGBA: Hashable, Codable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    public static let black = RGBA(r: 0, g: 0, b: 0)
    public static let white = RGBA(r: 1, g: 1, b: 1)
}
