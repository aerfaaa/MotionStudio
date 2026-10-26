import Foundation

/// An effect with every setting worked out for one moment in time.
public struct ResolvedEffect: Equatable {
    public var effectID: String
    /// Setting name to its numbers: one number for scalars, two (x, y) for vectors.
    public var values: [String: [Double]]

    public init(effectID: String, values: [String: [Double]]) {
        self.effectID = effectID
        self.values = values
    }
}

/// A layer with every animated value worked out for one moment in time.
/// A renderer never needs to know about keyframes, only about this.
public struct ResolvedLayer: Equatable, Identifiable {
    public var id: UUID
    public var kind: LayerKind
    /// Content size in composition pixels, before the transform.
    public var size: Vec2
    public var fill: RGBA
    /// 0...1
    public var opacity: Double
    public var blendMode: BlendMode
    /// Maps the layer's own pixels (top-left is 0,0) into composition pixels.
    /// Already includes any parent layers.
    public var transform: Affine2
    public var effects: [ResolvedEffect]

    public init(id: UUID, kind: LayerKind, size: Vec2, fill: RGBA, opacity: Double,
                blendMode: BlendMode, transform: Affine2, effects: [ResolvedEffect]) {
        self.id = id
        self.kind = kind
        self.size = size
        self.fill = fill
        self.opacity = opacity
        self.blendMode = blendMode
        self.transform = transform
        self.effects = effects
    }
}

/// Everything a renderer needs to draw one frame, and nothing else.
///
/// This is the contract between the editor's brain and any renderer. The V1 renderer
/// draws it with SwiftUI Canvas. A future Metal renderer and a future video exporter will
/// consume exactly the same value.
public struct ResolvedFrame: Equatable {
    public var frameIndex: Int64
    public var time: Time
    public var width: Int
    public var height: Int
    public var background: RGBA
    /// In drawing order: the first layer is drawn first (bottom), the last is on top.
    public var layers: [ResolvedLayer]

    public init(frameIndex: Int64, time: Time, width: Int, height: Int,
                background: RGBA, layers: [ResolvedLayer]) {
        self.frameIndex = frameIndex
        self.time = time
        self.width = width
        self.height = height
        self.background = background
        self.layers = layers
    }
}

/// Turns a composition and a moment in time into a `ResolvedFrame`. Pure maths: no drawing,
/// no screen, no files. That makes it easy to test, and safe to call from any thread.
public enum Evaluator {

    /// Resolve a whole frame by frame number. This is what preview and export should use.
    public static func resolve(_ composition: Composition, frame: Int64) -> ResolvedFrame {
        resolve(composition, at: composition.frameRate.time(ofFrame: frame), frameIndex: frame)
    }

    /// Resolve at any time (for example half a frame in, for motion blur later).
    public static func resolve(_ composition: Composition, at time: Time) -> ResolvedFrame {
        resolve(composition, at: time, frameIndex: composition.frameRate.frameIndex(at: time))
    }

    private static func resolve(_ composition: Composition, at time: Time, frameIndex: Int64) -> ResolvedFrame {
        let layersByID = Dictionary(composition.layers.map { ($0.id, $0) },
                                    uniquingKeysWith: { first, _ in first })
        var resolved: [ResolvedLayer] = []

        // The array lists the top layer first, so walk it backwards to draw bottom-up.
        for layer in composition.layers.reversed() {
            guard layer.isVisible, layer.kind != .null else { continue }
            guard time >= layer.inPoint, time < layer.outPoint else { continue }

            let opacity = min(max(layer.opacity.value(at: time), 0), 1)
            let transform = worldTransform(of: layer, at: time, layersByID: layersByID)
            resolved.append(ResolvedLayer(
                id: layer.id,
                kind: layer.kind,
                size: layer.size,
                fill: layer.fill,
                opacity: opacity,
                blendMode: layer.blendMode,
                transform: transform,
                effects: resolveEffects(layer.effects, at: time)))
        }

        return ResolvedFrame(frameIndex: frameIndex, time: time,
                             width: composition.width, height: composition.height,
                             background: composition.background, layers: resolved)
    }

    // MARK: Transforms

    /// The layer's own transform: move to position, rotate, scale, all around the anchor point.
    public static func localTransform(of layer: Layer, at time: Time) -> Affine2 {
        let position = layer.position.value(at: time)
        let scale = layer.scale.value(at: time)
        let anchor = layer.anchor.value(at: time)
        let rotation = layer.rotation.value(at: time)
        return Affine2.translation(position.x, position.y)
            .concatenating(Affine2.rotation(degrees: rotation))
            .concatenating(Affine2.scale(scale.x, scale.y))
            .concatenating(Affine2.translation(-anchor.x, -anchor.y))
    }

    /// The layer's transform including all its parents. A parent loop is cut off safely.
    public static func worldTransform(of layer: Layer, at time: Time,
                                      layersByID: [UUID: Layer]) -> Affine2 {
        var matrix = localTransform(of: layer, at: time)
        var visited: Set<UUID> = [layer.id]
        var current = layer
        while let parentID = current.parentID,
              let parent = layersByID[parentID],
              !visited.contains(parentID) {
            visited.insert(parentID)
            matrix = localTransform(of: parent, at: time).concatenating(matrix)
            current = parent
        }
        return matrix
    }

    private static func resolveEffects(_ effects: [EffectInstance], at time: Time) -> [ResolvedEffect] {
        var result: [ResolvedEffect] = []
        for effect in effects where effect.isEnabled {
            var values: [String: [Double]] = [:]
            for (name, parameter) in effect.parameters {
                switch parameter {
                case .scalar(let track):
                    values[name] = [track.value(at: time)]
                case .vector(let track):
                    let v = track.value(at: time)
                    values[name] = [v.x, v.y]
                }
            }
            result.append(ResolvedEffect(effectID: effect.effectID, values: values))
        }
        return result
    }

    // MARK: Hit testing

    /// Which layer is under a point (in composition pixels)? Returns the top-most one.
    public static func hitTest(_ frame: ResolvedFrame, at point: Vec2) -> UUID? {
        for layer in frame.layers.reversed() {
            guard layer.opacity > 0, let inverse = layer.transform.inverted() else { continue }
            let local = inverse.applying(to: point)
            guard local.x >= 0, local.x <= layer.size.x, local.y >= 0, local.y <= layer.size.y else { continue }
            if case .shape(.ellipse) = layer.kind {
                let rx = layer.size.x / 2
                let ry = layer.size.y / 2
                guard rx > 0, ry > 0 else { continue }
                let nx = (local.x - rx) / rx
                let ny = (local.y - ry) / ry
                if nx * nx + ny * ny > 1 { continue }
            }
            return layer.id
        }
        return nil
    }
}
