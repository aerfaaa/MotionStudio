import Foundation

/// An effect with every setting worked out for one moment in time.
public struct ResolvedEffect: Hashable {
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
    /// Transform samples used to draw a temporal trail for the motion-blur effect.
    /// The main transform is still drawn at full opacity after these samples.
    public var motionBlurTransforms: [Affine2]
    public var motionBlurTrailOpacity: Double
    public var id: UUID
    public var kind: LayerKind
    public var textFontName: String?
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
    /// Source timestamp for video layers after applying the layer playback rate.
    public var videoSourceTimeSeconds: Double?
    public var playbackSpeed: Double

    public init(id: UUID, kind: LayerKind, textFontName: String? = nil, size: Vec2, fill: RGBA, opacity: Double,
                blendMode: BlendMode, transform: Affine2, effects: [ResolvedEffect],
                motionBlurTransforms: [Affine2] = [], motionBlurTrailOpacity: Double = 0.14,
                videoSourceTimeSeconds: Double? = nil, playbackSpeed: Double = 1) {
        self.motionBlurTransforms = motionBlurTransforms
        self.motionBlurTrailOpacity = motionBlurTrailOpacity
        self.id = id
        self.kind = kind
        self.textFontName = textFontName
        self.size = size
        self.fill = fill
        self.opacity = opacity
        self.blendMode = blendMode
        self.transform = transform
        self.effects = effects
        self.videoSourceTimeSeconds = videoSourceTimeSeconds
        self.playbackSpeed = playbackSpeed
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

        // Adjustment layers affect only visual layers beneath them in the stack. Index zero is
        // topmost, so lower numeric indices are above the layer being rendered. Effects are
        // evaluated on each underlying layer before compositing; this is a useful first-class
        // adjustment workflow without requiring a full-canvas readback from SwiftUI Canvas.
        let activeAdjustments: [(index: Int, layer: Layer)] = composition.layers.enumerated().compactMap { index, layer in
            guard case .adjustment = layer.kind,
                  layer.isVisible,
                  time >= layer.inPoint, time < layer.outPoint,
                  layer.opacity.value(at: animationTime(for: layer, at: time)) > 0,
                  layer.effects.contains(where: \.isEnabled) else { return nil }
            return (index, layer)
        }

        // The array lists the top layer first, so walk it backwards to draw bottom-up.
        for (layerIndex, layer) in composition.layers.enumerated().reversed() {
            guard layer.isVisible, layer.kind != .null else { continue }
            guard time >= layer.inPoint, time < layer.outPoint else { continue }
            if case .adjustment = layer.kind { continue } // effects only; never draws a rectangle

            let sampleTime = animationTime(for: layer, at: time)
            let opacity = min(max(layer.opacity.value(at: sampleTime), 0), 1)
            let transform = worldTransform(of: layer, at: time, layersByID: layersByID)
            let adjustmentEffects = activeAdjustments
                .filter { $0.index < layerIndex }
                .sorted { $0.index > $1.index } // nearest adjustment first; topmost adjustment last
                .flatMap { resolveEffects($0.layer.effects, at: animationTime(for: $0.layer, at: time)) }
            let resolvedEffects = resolveEffects(layer.effects, at: sampleTime) + adjustmentEffects
            var blurTransforms: [Affine2] = []
            var blurTrailOpacity = 0.14
            if let blur = resolvedEffects.first(where: { $0.effectID == "motion-blur" }) {
                let shutter = min(720, max(0, blur.values["shutterAngle"]?.first ?? 180)) / 360
                let requestedSamples = Int(blur.values["samples"]?.first ?? 8)
                let sampleCount = min(16, max(2, requestedSamples))
                let halfWindow = (1.0 / composition.frameRate.framesPerSecond) * shutter * 0.5
                if halfWindow > 0.0001 {
                    // Sample both sides of the current time. This captures actual keyframed
                    // position/scale/rotation changes rather than merely blurring the source bitmap.
                    for sample in 0..<sampleCount {
                        let fraction = (Double(sample) + 0.5) / Double(sampleCount) * 2 - 1
                        let sampleTicks = time.ticks + Int64((fraction * halfWindow * Double(Time.ticksPerSecond)).rounded())
                        let sampleTime = Time(ticks: min(max(sampleTicks, layer.inPoint.ticks), max(layer.inPoint.ticks, layer.outPoint.ticks - 1)))
                        if sampleTime == time { continue }
                        let sampled = worldTransform(of: layer, at: sampleTime, layersByID: layersByID)
                        if sampled != transform { blurTransforms.append(sampled) }
                    }
                    blurTrailOpacity = min(0.22, max(0.04, 0.7 / Double(blurTransforms.count + 1)))
                }
            }
            resolved.append(ResolvedLayer(
                id: layer.id,
                kind: layer.kind,
                textFontName: layer.textFontName,
                size: layer.size,
                fill: layer.fill,
                opacity: opacity,
                blendMode: layer.blendMode,
                transform: transform,
                effects: resolvedEffects,
                motionBlurTransforms: blurTransforms,
                motionBlurTrailOpacity: blurTrailOpacity,
                videoSourceTimeSeconds: { if case .video = layer.kind, layer.effects.contains(where: { $0.effectID == "optical-flow-slow-motion" && $0.isEnabled }) { return max(0, Double(time.ticks - layer.inPoint.ticks) / Double(Time.ticksPerSecond) * layer.playbackSpeed) }; return nil }(),
                playbackSpeed: layer.playbackSpeed))
        }

        return ResolvedFrame(frameIndex: frameIndex, time: time,
                             width: composition.width, height: composition.height,
                             background: composition.background, layers: resolved)
    }

    // MARK: Transforms

    /// The layer's own transform: move to position, rotate, scale, all around the anchor point.
    public static func localTransform(of layer: Layer, at time: Time) -> Affine2 {
        let sampleTime = animationTime(for: layer, at: time)
        let position = layer.position.value(at: sampleTime)
        let scale = layer.scale.value(at: sampleTime)
        let anchor = layer.anchor.value(at: sampleTime)
        let rotation = layer.rotation.value(at: sampleTime)
        return Affine2.translation(position.x, position.y)
            .concatenating(Affine2.rotation(degrees: rotation))
            .concatenating(Affine2.scale(scale.x, scale.y))
            .concatenating(Affine2.translation(-anchor.x, -anchor.y))
    }

    /// Map composition time to the layer's animation clock. The layer's visible in/out range remains
    /// in composition time; only keyframed motion and effect parameters are time-stretched.
    public static func animationTime(for layer: Layer, at time: Time) -> Time {
        let speed = min(max(layer.playbackSpeed.isFinite ? layer.playbackSpeed : 1, 0.1), 4)
        let elapsed = Double(time.ticks - layer.inPoint.ticks) * speed
        let ticks = Double(layer.inPoint.ticks) + elapsed
        return Time(ticks: Int64(min(max(ticks, -Double(Time.maximumDuration.ticks)), Double(Time.maximumDuration.ticks)).rounded()))
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
