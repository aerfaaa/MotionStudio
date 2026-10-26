import Foundation

/// How to travel from a keyframe to the NEXT one.
public enum Interpolation: Hashable, Codable, Sendable {
    /// Stay on this value until the next keyframe, then jump.
    case hold
    case linear
    case bezier(BezierEase)
}

public struct Keyframe<Value: Codable & Equatable>: Codable, Equatable {
    public var time: Time
    public var value: Value
    /// Stored on the keyframe where the segment STARTS.
    public var outgoing: Interpolation

    public init(time: Time, value: Value, outgoing: Interpolation = .linear) {
        self.time = time
        self.value = value
        self.outgoing = outgoing
    }
}

/// A value that can change over time. With no keyframes it is a plain fixed value.
public struct AnimatedProperty<Value: Interpolatable & Codable & Equatable>: Codable, Equatable {
    /// Used whenever there are no keyframes.
    public var staticValue: Value
    /// Always sorted by time, never two at the same time.
    public private(set) var keyframes: [Keyframe<Value>]

    public init(_ staticValue: Value, keyframes: [Keyframe<Value>] = []) {
        self.staticValue = staticValue
        self.keyframes = AnimatedProperty.normalised(keyframes)
    }

    public var isAnimated: Bool { !keyframes.isEmpty }

    public func keyframe(at time: Time) -> Keyframe<Value>? {
        keyframes.first(where: { $0.time == time })
    }

    public func hasKeyframe(at time: Time) -> Bool {
        keyframe(at: time) != nil
    }

    /// The value at a moment in time.
    public func value(at time: Time) -> Value {
        guard let first = keyframes.first, let last = keyframes.last else { return staticValue }
        if time <= first.time { return first.value }
        if time >= last.time { return last.value }

        // Binary search. `low` always has time <= `time`; `high` always has time > `time`.
        var low = 0
        var high = keyframes.count - 1
        while high - low > 1 {
            let middle = (low + high) / 2
            if keyframes[middle].time <= time {
                low = middle
            } else {
                high = middle
            }
        }
        let from = keyframes[low]
        let to = keyframes[high]
        let span = Double(to.time.ticks - from.time.ticks)
        let progress = Double(time.ticks - from.time.ticks) / span

        switch from.outgoing {
        case .hold:
            return from.value
        case .linear:
            return Value.interpolate(from: from.value, to: to.value, progress: progress)
        case .bezier(let ease):
            return Value.interpolate(from: from.value, to: to.value, progress: ease.solve(progress))
        }
    }

    /// Adds a keyframe, or replaces the one already at that time.
    public mutating func setKeyframe(at time: Time, value: Value, interpolation: Interpolation = .linear) {
        let new = Keyframe(time: time, value: value, outgoing: interpolation)
        if let index = keyframes.firstIndex(where: { $0.time == time }) {
            keyframes[index] = new
        } else {
            let insertAt = keyframes.firstIndex(where: { $0.time > time }) ?? keyframes.count
            keyframes.insert(new, at: insertAt)
        }
    }

    /// Removes the keyframe at that time. If it was the last one, the property becomes a
    /// fixed value equal to what that keyframe held.
    @discardableResult
    public mutating func removeKeyframe(at time: Time) -> Bool {
        guard let index = keyframes.firstIndex(where: { $0.time == time }) else { return false }
        let removed = keyframes.remove(at: index)
        if keyframes.isEmpty {
            staticValue = removed.value
        }
        return true
    }

    // MARK: Saving. Loading also repairs the order, so a hand-edited file cannot break playback.

    private enum CodingKeys: String, CodingKey {
        case staticValue, keyframes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let staticValue = try container.decode(Value.self, forKey: .staticValue)
        let keyframes = try container.decodeIfPresent([Keyframe<Value>].self, forKey: .keyframes) ?? []
        self.init(staticValue, keyframes: keyframes)
    }

    private static func normalised(_ keyframes: [Keyframe<Value>]) -> [Keyframe<Value>] {
        var result: [Keyframe<Value>] = []
        for keyframe in keyframes.sorted(by: { $0.time < $1.time }) {
            if let last = result.last, last.time == keyframe.time {
                result[result.count - 1] = keyframe
            } else {
                result.append(keyframe)
            }
        }
        return result
    }
}

// MARK: - Keyframe editing and curve lookup

extension AnimatedProperty {

    /// Moves a keyframe to a new time, keeping its value and easing. Throws if there is no keyframe
    /// at `from`, or another keyframe already sits at `to`.
    public mutating func moveKeyframe(from: Time, to: Time) throws {
        guard let index = keyframes.firstIndex(where: { $0.time == from }) else {
            throw EditError.keyframeNotFound
        }
        if from == to { return }
        guard !keyframes.contains(where: { $0.time == to }) else {
            throw EditError.keyframeOccupied
        }
        var moved = keyframes.remove(at: index)
        moved.time = to
        let insertAt = keyframes.firstIndex(where: { $0.time > to }) ?? keyframes.count
        keyframes.insert(moved, at: insertAt)
    }

    /// Changes how the animation travels from the keyframe at `time` to the next one.
    public mutating func setInterpolation(at time: Time, to interpolation: Interpolation) throws {
        guard let index = keyframes.firstIndex(where: { $0.time == time }) else {
            throw EditError.keyframeNotFound
        }
        keyframes[index].outgoing = interpolation
    }

    /// The pair of keyframes that surround `time`, and how far through them it is (0...1).
    /// Returns nil before the first keyframe, at or after the last one, or with fewer than two keyframes.
    public func segment(at time: Time) -> (from: Keyframe<Value>, to: Keyframe<Value>, progress: Double)? {
        guard keyframes.count >= 2,
              let first = keyframes.first, let last = keyframes.last,
              time >= first.time, time < last.time else { return nil }
        var low = 0
        var high = keyframes.count - 1
        while high - low > 1 {
            let middle = (low + high) / 2
            if keyframes[middle].time <= time { low = middle } else { high = middle }
        }
        let from = keyframes[low]
        let to = keyframes[high]
        let span = Double(to.time.ticks - from.time.ticks)
        return (from, to, Double(time.ticks - from.time.ticks) / span)
    }
}

// MARK: - Speed (the maths behind a Speed Graph)

extension AnimatedProperty where Value == Double {
    /// How fast the value is changing at `time`, in units per second. Zero outside the keyframes
    /// and on "hold" segments.
    public func speed(at time: Time) -> Double {
        guard let seg = self.segment(at: time) else { return 0 }
        let seconds = (seg.to.time - seg.from.time).seconds
        guard seconds > 0 else { return 0 }
        let change = seg.to.value - seg.from.value
        switch seg.from.outgoing {
        case .hold: return 0
        case .linear: return change / seconds
        case .bezier(let ease): return change / seconds * ease.derivative(at: seg.progress)
        }
    }

    /// The value at evenly spaced times, for drawing a Value Graph.
    public func sampledValues(from start: Time, to end: Time, count: Int) -> [(time: Time, value: Double)] {
        guard count >= 2, end > start else { return [] }
        return (0..<count).map { (i: Int) -> (time: Time, value: Double) in
            let ticks = start.ticks + (end.ticks - start.ticks) * Int64(i) / Int64(count - 1)
            let sampleTime = Time(ticks: ticks)
            return (sampleTime, self.value(at: sampleTime))
        }
    }
}

extension AnimatedProperty where Value == Vec2 {
    /// Speed of a two-number property: the length of its velocity, in units per second.
    public func speed(at time: Time) -> Double {
        guard let seg = self.segment(at: time) else { return 0 }
        let seconds = (seg.to.time - seg.from.time).seconds
        guard seconds > 0 else { return 0 }
        let distance = (seg.to.value - seg.from.value).length
        switch seg.from.outgoing {
        case .hold: return 0
        case .linear: return distance / seconds
        case .bezier(let ease): return distance / seconds * abs(ease.derivative(at: seg.progress))
        }
    }
}
