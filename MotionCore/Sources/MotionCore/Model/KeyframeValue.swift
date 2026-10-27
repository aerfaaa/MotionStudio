import Foundation

/// A keyframe's value, whichever kind of property it belongs to.
public enum KeyframeValue: Codable, Equatable {
    case scalar(Double)
    case vector(Vec2)
}

/// A keyframe copied out of a layer, so it can be shown, copied and pasted.
public struct KeyframeSnapshot: Equatable {
    public var time: Time
    public var value: KeyframeValue
    public var outgoing: Interpolation

    public init(time: Time, value: KeyframeValue, outgoing: Interpolation) {
        self.time = time
        self.value = value
        self.outgoing = outgoing
    }
}

extension Layer {
    /// All keyframes of one property, in time order.
    public func keyframeSnapshots(_ key: PropertyKey) -> [KeyframeSnapshot] {
        if let track = vectorTrack(key) {
            return track.keyframes.map { KeyframeSnapshot(time: $0.time, value: .vector($0.value), outgoing: $0.outgoing) }
        }
        if let track = scalarTrack(key) {
            return track.keyframes.map { KeyframeSnapshot(time: $0.time, value: .scalar($0.value), outgoing: $0.outgoing) }
        }
        return []
    }

    public func keyframeSnapshot(_ key: PropertyKey, at time: Time) -> KeyframeSnapshot? {
        keyframeSnapshots(key).first(where: { $0.time == time })
    }

    /// Adds or replaces a keyframe. The value kind must match the property (two numbers for position, one for opacity...).
    public mutating func insertKeyframe(_ key: PropertyKey, _ snapshot: KeyframeSnapshot) throws {
        switch snapshot.value {
        case .vector(let value):
            guard var track = vectorTrack(key) else { throw EditError.invalidProperty }
            track.setKeyframe(at: snapshot.time, value: value, interpolation: snapshot.outgoing)
            setVectorTrack(key, track)
        case .scalar(let value):
            guard var track = scalarTrack(key) else { throw EditError.invalidProperty }
            track.setKeyframe(at: snapshot.time, value: value, interpolation: snapshot.outgoing)
            setScalarTrack(key, track)
        }
    }

    public mutating func moveKeyframe(_ key: PropertyKey, from: Time, to: Time) throws {
        if var track = vectorTrack(key) {
            try track.moveKeyframe(from: from, to: to)
            setVectorTrack(key, track)
        } else if var track = scalarTrack(key) {
            try track.moveKeyframe(from: from, to: to)
            setScalarTrack(key, track)
        } else {
            throw EditError.invalidProperty
        }
    }

    public mutating func setKeyframeInterpolation(_ key: PropertyKey, at time: Time,
                                                  to interpolation: Interpolation) throws {
        if var track = vectorTrack(key) {
            try track.setInterpolation(at: time, to: interpolation)
            setVectorTrack(key, track)
        } else if var track = scalarTrack(key) {
            try track.setInterpolation(at: time, to: interpolation)
            setScalarTrack(key, track)
        } else {
            throw EditError.invalidProperty
        }
    }
}
