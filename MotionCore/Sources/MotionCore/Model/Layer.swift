import Foundation

public enum ShapeKind: String, Codable, Sendable {
    case rectangle
    case ellipse
}

/// What a layer is. The project stores media references by asset ID; renderers decide how each kind is drawn.
public enum LayerKind: Codable, Equatable {
    /// A flat coloured rectangle.
    case solid
    case shape(ShapeKind)
    /// A still image from the project's media folder.
    case image(assetID: UUID)
    /// A video asset. The current preview displays its poster frame; real-time video playback is a later renderer task.
    case video(assetID: UUID)
    /// An audio-only clip. It appears on the timeline but is not drawn into the composition.
    case audio(assetID: UUID)
    /// Editable text content.
    case text(String)
    /// Draws nothing. Useful as an invisible parent that other layers follow.
    case null
}

/// One layer in a composition.
///
/// Transform rules (the same as After Effects):
/// - `anchor` is a point on the layer, in layer pixels from its top-left corner.
/// - `position` is where in the composition that anchor point sits.
/// - Scale and rotation happen around the anchor point.
/// - `scale` of (1, 1) means 100 percent. `rotation` is in degrees, clockwise.
public struct Layer: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var kind: LayerKind
    /// Optional registered PostScript font name for text layers. Nil means the system font.
    public var textFontName: String?
    /// Size of the layer's content in composition pixels, before scale.
    public var size: Vec2
    public var fill: RGBA
    /// The layer exists from `inPoint` up to (not including) `outPoint`.
    public var inPoint: Time
    public var outPoint: Time
    public var position: AnimatedProperty<Vec2>
    public var scale: AnimatedProperty<Vec2>
    public var anchor: AnimatedProperty<Vec2>
    public var rotation: AnimatedProperty<Double>
    /// 0 is invisible, 1 is fully visible.
    public var opacity: AnimatedProperty<Double>
    public var blendMode: BlendMode
    /// When set, this layer's transform is relative to the parent layer's transform.
    public var parentID: UUID?
    public var isVisible: Bool
    public var effects: [EffectInstance]

    public init(id: UUID = UUID(),
                name: String,
                kind: LayerKind,
                textFontName: String? = nil,
                size: Vec2,
                fill: RGBA,
                inPoint: Time,
                outPoint: Time,
                position: Vec2,
                anchor: Vec2? = nil,
                scale: Vec2 = .one,
                rotation: Double = 0,
                opacity: Double = 1,
                blendMode: BlendMode = .normal,
                parentID: UUID? = nil,
                isVisible: Bool = true,
                effects: [EffectInstance] = []) {
        self.id = id
        self.name = name
        self.kind = kind
        self.textFontName = textFontName
        self.size = size
        self.fill = fill
        self.inPoint = inPoint
        self.outPoint = outPoint
        self.position = AnimatedProperty(position)
        self.scale = AnimatedProperty(scale)
        self.anchor = AnimatedProperty(anchor ?? Vec2(x: size.x / 2, y: size.y / 2))
        self.rotation = AnimatedProperty(rotation)
        self.opacity = AnimatedProperty(opacity)
        self.blendMode = blendMode
        self.parentID = parentID
        self.isVisible = isVisible
        self.effects = effects
    }

    // MARK: Saving. Fields added after version 1 use decodeIfPresent so older files still open.

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, textFontName, size, fill, inPoint, outPoint
        case position, scale, anchor, rotation, opacity
        case blendMode, parentID, isVisible, effects
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decode(LayerKind.self, forKey: .kind)
        textFontName = try c.decodeIfPresent(String.self, forKey: .textFontName)
        size = try c.decode(Vec2.self, forKey: .size)
        fill = try c.decode(RGBA.self, forKey: .fill)
        inPoint = try c.decode(Time.self, forKey: .inPoint)
        outPoint = try c.decode(Time.self, forKey: .outPoint)
        position = try c.decode(AnimatedProperty<Vec2>.self, forKey: .position)
        scale = try c.decode(AnimatedProperty<Vec2>.self, forKey: .scale)
        anchor = try c.decode(AnimatedProperty<Vec2>.self, forKey: .anchor)
        rotation = try c.decode(AnimatedProperty<Double>.self, forKey: .rotation)
        opacity = try c.decode(AnimatedProperty<Double>.self, forKey: .opacity)
        blendMode = try c.decodeIfPresent(BlendMode.self, forKey: .blendMode) ?? .normal
        parentID = try c.decodeIfPresent(UUID.self, forKey: .parentID)
        isVisible = try c.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true
        effects = try c.decodeIfPresent([EffectInstance].self, forKey: .effects) ?? []
    }
}

// MARK: - Reading and changing properties by name

extension Layer {
    public func vectorTrack(_ key: PropertyKey) -> AnimatedProperty<Vec2>? {
        switch key {
        case .position: return position
        case .scale: return scale
        case .anchor: return anchor
        case .rotation, .opacity: return nil
        }
    }

    public func scalarTrack(_ key: PropertyKey) -> AnimatedProperty<Double>? {
        switch key {
        case .rotation: return rotation
        case .opacity: return opacity
        case .position, .scale, .anchor: return nil
        }
    }

    public mutating func setVectorTrack(_ key: PropertyKey, _ track: AnimatedProperty<Vec2>) {
        switch key {
        case .position: position = track
        case .scale: scale = track
        case .anchor: anchor = track
        case .rotation, .opacity: break
        }
    }

    public mutating func setScalarTrack(_ key: PropertyKey, _ track: AnimatedProperty<Double>) {
        switch key {
        case .rotation: rotation = track
        case .opacity: opacity = track
        case .position, .scale, .anchor: break
        }
    }

    public func isAnimated(_ key: PropertyKey) -> Bool {
        if let track = vectorTrack(key) { return track.isAnimated }
        if let track = scalarTrack(key) { return track.isAnimated }
        return false
    }

    public func hasKeyframe(_ key: PropertyKey, at time: Time) -> Bool {
        if let track = vectorTrack(key) { return track.hasKeyframe(at: time) }
        if let track = scalarTrack(key) { return track.hasKeyframe(at: time) }
        return false
    }

    public func vectorValue(_ key: PropertyKey, at time: Time) -> Vec2? {
        vectorTrack(key)?.value(at: time)
    }

    public func scalarValue(_ key: PropertyKey, at time: Time) -> Double? {
        scalarTrack(key)?.value(at: time)
    }

    /// Every time that has a keyframe on any property, sorted, without repeats. Used to draw the timeline.
    public var keyframeTimes: [Time] {
        var times = Set<Time>()
        for key in PropertyKey.allCases {
            if let track = vectorTrack(key) {
                for keyframe in track.keyframes { times.insert(keyframe.time) }
            }
            if let track = scalarTrack(key) {
                for keyframe in track.keyframes { times.insert(keyframe.time) }
            }
        }
        return times.sorted()
    }

    /// Sets a value. If the property already has keyframes, the edit becomes a keyframe at `time`
    /// (like After Effects' auto-keyframing). If not, it simply changes the fixed value.
    public mutating func setVector(_ key: PropertyKey, to value: Vec2, at time: Time) throws {
        guard var track = vectorTrack(key) else { throw EditError.invalidProperty }
        if track.isAnimated {
            let existing = track.keyframe(at: time)?.outgoing ?? .linear
            track.setKeyframe(at: time, value: value, interpolation: existing)
        } else {
            track.staticValue = value
        }
        setVectorTrack(key, track)
    }

    public mutating func setScalar(_ key: PropertyKey, to value: Double, at time: Time) throws {
        guard var track = scalarTrack(key) else { throw EditError.invalidProperty }
        if track.isAnimated {
            let existing = track.keyframe(at: time)?.outgoing ?? .linear
            track.setKeyframe(at: time, value: value, interpolation: existing)
        } else {
            track.staticValue = value
        }
        setScalarTrack(key, track)
    }

    /// Adds a keyframe holding the property's current value at `time`.
    public mutating func addKeyframe(_ key: PropertyKey, at time: Time) throws {
        if var track = vectorTrack(key) {
            if !track.hasKeyframe(at: time) {
                track.setKeyframe(at: time, value: track.value(at: time))
            }
            setVectorTrack(key, track)
        } else if var track = scalarTrack(key) {
            if !track.hasKeyframe(at: time) {
                track.setKeyframe(at: time, value: track.value(at: time))
            }
            setScalarTrack(key, track)
        } else {
            throw EditError.invalidProperty
        }
    }

    public mutating func removeKeyframe(_ key: PropertyKey, at time: Time) throws {
        if var track = vectorTrack(key) {
            track.removeKeyframe(at: time)
            setVectorTrack(key, track)
        } else if var track = scalarTrack(key) {
            track.removeKeyframe(at: time)
            setScalarTrack(key, track)
        } else {
            throw EditError.invalidProperty
        }
    }
}
