import Foundation

/// A speed curve between two keyframes, described the same way as CSS `cubic-bezier(x1, y1, x2, y2)`.
/// The curve starts at (0, 0) and ends at (1, 1); the two numbers pairs are its handles.
public struct BezierEase: Hashable, Codable, Sendable {
    public var x1: Double
    public var y1: Double
    public var x2: Double
    public var y2: Double

    public init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        self.x1 = x1
        self.y1 = y1
        self.x2 = x2
        self.y2 = y2
    }

    public static let easeIn = BezierEase(0.42, 0, 1, 1)
    public static let easeOut = BezierEase(0, 0, 0.58, 1)
    public static let easeInOut = BezierEase(0.42, 0, 0.58, 1)

    /// Given how far through time we are (0...1), returns how far through the change we are.
    /// Finds the curve position with the bisection method, which is slow-ish but cannot fail.
    public func solve(_ time: Double) -> Double {
        if time <= 0 { return 0 }
        if time >= 1 { return 1 }
        // Horizontal handles must stay inside 0...1 so the curve never doubles back in time.
        let h1 = min(max(x1, 0), 1)
        let h2 = min(max(x2, 0), 1)
        var low = 0.0
        var high = 1.0
        for _ in 0..<50 {
            let middle = (low + high) / 2
            if BezierEase.cubic(middle, h1, h2) < time {
                low = middle
            } else {
                high = middle
            }
        }
        return BezierEase.cubic((low + high) / 2, y1, y2)
    }

    private static func cubic(_ s: Double, _ p1: Double, _ p2: Double) -> Double {
        let u = 1 - s
        return 3 * u * u * s * p1 + 3 * u * s * s * p2 + s * s * s
    }
}
