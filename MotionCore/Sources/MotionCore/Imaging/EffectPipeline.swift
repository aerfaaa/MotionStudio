import Foundation

/// Something that went wrong while applying an effect. The picture is still produced; the effect is skipped.
public struct EffectIssue: Equatable {
    public let effectID: String
    public let message: String

    public init(effectID: String, message: String) {
        self.effectID = effectID
        self.message = message
    }
}

/// Applies a layer's effects, in order, to a picture.
///
/// `scale` is how many bitmap pixels there are for each layer pixel. Effect settings measured in pixels
/// (blur radius, shadow distance, block size...) are written in layer pixels and multiplied by `scale`, so a
/// preview made from a smaller copy of the picture looks the same as the full-size result.
public enum EffectPipeline {

    /// True when at least one effect in the list can actually be processed.
    public static func hasWork(_ effects: [ResolvedEffect]) -> Bool {
        effects.contains(where: { $0.effectID != "motion-blur" && ImageEffects.isAvailable($0.effectID) })
    }

    public static func apply(_ effects: [ResolvedEffect], to image: PixelImage,
                             scale: Double) -> (image: PixelImage, issues: [EffectIssue]) {
        var current = image
        var issues: [EffectIssue] = []
        guard scale.isFinite, scale > 0 else {
            return (image, [EffectIssue(effectID: "", message: "The preview scale is invalid.")])
        }
        for effect in effects {
            // Motion blur is temporal and transform-based. It is rendered by the composition
            // renderer from Evaluator.motionBlurTransforms, never baked into a still bitmap.
            if effect.effectID == "motion-blur" { continue }
            guard let process = ImageEffects.processor(for: effect.effectID) else {
                let known = EffectRegistry.definition(id: effect.effectID)
                issues.append(EffectIssue(
                    effectID: effect.effectID,
                    message: known == nil ? "Unknown effect \"\(effect.effectID)\" was skipped."
                                          : "\(known?.name ?? effect.effectID) cannot be processed yet and was skipped."))
                continue
            }
            let values = EffectValues(resolved: effect)
            let result = process(current, values, scale)
            guard result.pixels.count == result.width * result.height * 4, !result.isEmpty else {
                issues.append(EffectIssue(effectID: effect.effectID, message: "The effect produced an invalid picture and was skipped."))
                continue
            }
            // Each processor keeps the picture's origin up to date (a shadow that grows the canvas moves it).
            current = result
        }
        return (current, issues)
    }
}
