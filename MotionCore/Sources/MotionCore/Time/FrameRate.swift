import Foundation

/// A frame rate stored as an exact fraction: `numerator` frames every `denominator` seconds.
///
/// 29.97 fps is `30000 / 1001`. It is never stored as the decimal 29.97.
///
/// Frame times are always calculated from the frame NUMBER (`time(ofFrame:)`) and
/// never by adding up frame durations, so they cannot drift however long the project is.
public struct FrameRate: Hashable, Codable, Sendable {
    public let numerator: Int64
    public let denominator: Int64

    /// Returns nil unless both numbers are positive and sensible. The fraction is reduced (50/2 becomes 25/1).
    public init?(numerator: Int64, denominator: Int64 = 1) {
        guard numerator > 0, denominator > 0, denominator < 1_000_000, numerator < 1_000_000_000 else { return nil }
        let divisor = FrameRate.greatestCommonDivisor(numerator, denominator)
        self.numerator = numerator / divisor
        self.denominator = denominator / divisor
    }

    // Common rates. The force-unwraps are safe: these are fixed, valid numbers.
    public static let fps23_976 = FrameRate(numerator: 24000, denominator: 1001)!
    public static let fps24 = FrameRate(numerator: 24)!
    public static let fps25 = FrameRate(numerator: 25)!
    public static let fps29_97 = FrameRate(numerator: 30000, denominator: 1001)!
    public static let fps30 = FrameRate(numerator: 30)!
    public static let fps50 = FrameRate(numerator: 50)!
    public static let fps59_94 = FrameRate(numerator: 60000, denominator: 1001)!
    public static let fps60 = FrameRate(numerator: 60)!
    public static let fps120 = FrameRate(numerator: 120)!

    public var framesPerSecond: Double {
        Double(numerator) / Double(denominator)
    }

    /// True when one frame lasts a whole number of ticks. For these rates the
    /// frame timeline is perfectly exact. Others are rounded once per frame (see `time(ofFrame:)`).
    public var hasExactTickFrames: Bool {
        (Time.ticksPerSecond * denominator) % numerator == 0
    }

    /// Human readable, e.g. "24 fps" or "29.97 fps".
    public var displayName: String {
        if denominator == 1 { return "\(numerator) fps" }
        var text = String(format: "%.3f", framesPerSecond)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return "\(text) fps"
    }

    /// The start time of a frame: round(frame x ticksPerSecond x denominator / numerator).
    ///
    /// The result is rounded once, directly from the frame number, so the error is at most
    /// half a tick (a few nanoseconds) and never grows. For the standard rates it is exact.
    public func time(ofFrame frame: Int64) -> Time {
        let magnitude = frame < 0 ? -frame : frame
        let scale = Time.ticksPerSecond * denominator
        let product = magnitude.multipliedFullWidth(by: scale)
        let division = numerator.dividingFullWidth(product)
        var quotient = division.quotient
        if division.remainder >= numerator - division.remainder {
            quotient += 1 // round half up
        }
        return Time(ticks: frame < 0 ? -quotient : quotient)
    }

    /// The frame that is showing at `time`: the largest frame whose start time is <= `time`.
    public func frameIndex(at time: Time) -> Int64 {
        let scale = Time.ticksPerSecond * denominator
        let ticks = time.ticks
        let magnitude = ticks < 0 ? -ticks : ticks
        let product = magnitude.multipliedFullWidth(by: numerator)
        let division = scale.dividingFullWidth(product)
        var estimate = division.quotient
        if ticks < 0 {
            if division.remainder != 0 { estimate += 1 }
            estimate = -estimate
        }
        // The estimate can be off by one when frame times are rounded; settle it exactly.
        while self.time(ofFrame: estimate + 1) <= time { estimate += 1 }
        while self.time(ofFrame: estimate) > time { estimate -= 1 }
        return estimate
    }

    /// Moves a time to the start of the frame it falls in.
    public func snapped(_ time: Time) -> Time {
        self.time(ofFrame: frameIndex(at: time))
    }

    /// How many frames a composition of this length contains (frames that start before the end).
    public func frameCount(for duration: Time) -> Int64 {
        guard duration.ticks > 0 else { return 0 }
        var count = frameIndex(at: duration)
        if self.time(ofFrame: count) < duration { count += 1 }
        return count
    }

    // MARK: Saving

    private enum CodingKeys: String, CodingKey {
        case numerator, denominator
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let numerator = try container.decode(Int64.self, forKey: .numerator)
        let denominator = try container.decode(Int64.self, forKey: .denominator)
        guard let rate = FrameRate(numerator: numerator, denominator: denominator) else {
            throw DecodingError.dataCorruptedError(
                forKey: .numerator, in: container,
                debugDescription: "A frame rate needs a positive numerator and denominator.")
        }
        self = rate
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(numerator, forKey: .numerator)
        try container.encode(denominator, forKey: .denominator)
    }

    private static func greatestCommonDivisor(_ a: Int64, _ b: Int64) -> Int64 {
        var x = a
        var y = b
        while y != 0 {
            (x, y) = (y, x % y)
        }
        return x
    }
}
