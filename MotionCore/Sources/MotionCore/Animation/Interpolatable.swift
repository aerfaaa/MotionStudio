import Foundation

/// Anything that can be blended between two values, so it can be animated.
public protocol Interpolatable {
    /// `progress` of 0 gives `a`, 1 gives `b`.
    static func interpolate(from a: Self, to b: Self, progress: Double) -> Self
}

extension Double: Interpolatable {
    public static func interpolate(from a: Double, to b: Double, progress: Double) -> Double {
        a + (b - a) * progress
    }
}

extension Vec2: Interpolatable {
    public static func interpolate(from a: Vec2, to b: Vec2, progress: Double) -> Vec2 {
        Vec2(x: a.x + (b.x - a.x) * progress,
             y: a.y + (b.y - a.y) * progress)
    }
}
