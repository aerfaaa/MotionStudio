import Foundation

/// A point in time, or a length of time, stored as a whole number of "ticks".
///
/// Why ticks? Decimal seconds (0.1 + 0.2) are never exact in a computer, and tiny
/// errors pile up over a long edit. Whole numbers never drift.
///
/// There are 141,120,000 ticks in one second. That number was chosen because it is
/// divisible by every frame rate and audio sample rate this editor cares about
/// (see `FrameRate` and `Time.ticksPerAudioSample`). Unit tests prove it.
public struct Time: Hashable, Comparable, Codable, Sendable {
    public static let ticksPerSecond: Int64 = 141_120_000

    /// Longest composition the editor allows (24 hours). Keeps all maths far from overflow.
    public static let maximumDuration = Time(ticks: 24 * 3600 * ticksPerSecond)

    public static let zero = Time(ticks: 0)

    public var ticks: Int64

    public init(ticks: Int64) {
        self.ticks = ticks
    }

    public init(seconds: Double) {
        self.ticks = Int64((seconds * Double(Time.ticksPerSecond)).rounded())
    }

    public var seconds: Double {
        Double(ticks) / Double(Time.ticksPerSecond)
    }

    public static func < (lhs: Time, rhs: Time) -> Bool { lhs.ticks < rhs.ticks }
    public static func + (lhs: Time, rhs: Time) -> Time { Time(ticks: lhs.ticks + rhs.ticks) }
    public static func - (lhs: Time, rhs: Time) -> Time { Time(ticks: lhs.ticks - rhs.ticks) }

    /// Number of ticks in one audio sample, or nil if the sample rate does not divide evenly.
    /// For 44,100 Hz this is 3,200 and for 48,000 Hz it is 2,940.
    public static func ticksPerAudioSample(sampleRate: Int64) -> Int64? {
        guard sampleRate > 0, ticksPerSecond % sampleRate == 0 else { return nil }
        return ticksPerSecond / sampleRate
    }

    // Stored in JSON as one plain number.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.ticks = try container.decode(Int64.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(ticks)
    }
}
