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
