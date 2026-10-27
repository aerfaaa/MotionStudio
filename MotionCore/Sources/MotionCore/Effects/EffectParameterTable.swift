import Foundation

/// Setting lists for the effects whose parameters are already designed. Effects not listed here
/// are registered with an empty list until their design is written.
enum EffectParameterTable {

    private static func scalar(_ id: String, _ name: String, _ min: Double, _ max: Double,
                               _ defaultValue: Double) -> EffectParameterDefinition {
        EffectParameterDefinition(id: id, name: name,
                                  kind: .scalar(min: min, max: max, defaultValue: defaultValue))
    }

    private static func choice(_ id: String, _ name: String, _ options: [String],
                               _ defaultIndex: Int = 0) -> EffectParameterDefinition {
        EffectParameterDefinition(id: id, name: name,
                                  kind: .choice(options: options, defaultIndex: defaultIndex))
    }

    private static func vector(_ id: String, _ name: String, _ x: Double, _ y: Double) -> EffectParameterDefinition {
        EffectParameterDefinition(id: id, name: name, kind: .vector(defaultValue: Vec2(x: x, y: y)))
    }

    /// Colour settings are three numbers named <prefix>Red, <prefix>Green and <prefix>Blue.
    private static func colour(_ prefix: String, _ name: String, _ r: Double, _ g: Double, _ b: Double)
        -> [EffectParameterDefinition] {
        [scalar(prefix + "Red", name + " red", 0, 1, r),
         scalar(prefix + "Green", name + " green", 0, 1, g),
         scalar(prefix + "Blue", name + " blue", 0, 1, b)]
    }

    private static let dropShadowParameters: [EffectParameterDefinition] = {
        var list = colour("shadow", "Colour", 0, 0, 0)
        list.append(scalar("opacity", "Opacity", 0, 1, 0.6))
        list.append(scalar("blur", "Blur (pixels)", 0, 60, 12))
        list.append(scalar("distance", "Distance (pixels)", 0, 300, 20))
        list.append(scalar("angle", "Angle (degrees)", -360, 360, 45))
        list.append(scalar("spread", "Spread (pixels)", 0, 40, 0))
        return list
    }()

    private static let glowParameters: [EffectParameterDefinition] = {
        var list: [EffectParameterDefinition] = []
        list.append(scalar("threshold", "Threshold", 0, 1, 0.6))
        list.append(scalar("radius", "Radius (pixels)", 0, 100, 30))
        list.append(scalar("intensity", "Intensity", 0, 4, 1))
        list.append(contentsOf: colour("color", "Colour", 1, 1, 1))
        list.append(choice("mode", "Output", ["Keep original", "Glow only"], 0))
        return list
    }()

    private static let gradientMapParameters: [EffectParameterDefinition] = {
        var list = colour("low", "Shadows", 0.05, 0.05, 0.25)
        list.append(contentsOf: colour("mid", "Midtones", 0.8, 0.2, 0.5))
        list.append(contentsOf: colour("high", "Highlights", 1.0, 0.9, 0.4))
        list.append(scalar("midPosition", "Midtone position", 0.05, 0.95, 0.5))
        list.append(scalar("mix", "Mix with original", 0, 1, 1))
        return list
    }()

    static let parameters: [String: [EffectParameterDefinition]] = [
        // Stage A: colour
        "brightness-contrast": [
            scalar("brightness", "Brightness", -1, 1, 0),
            scalar("contrast", "Contrast", -1, 1, 0),
        ],
        "hue-shift": [
            scalar("degrees", "Hue shift (degrees)", -180, 180, 0),
        ],
        "saturation-vibrance": [
            scalar("saturation", "Saturation", 0, 3, 1),
        ],
        "invert": [],
        // Stage B: image quality
        "gaussian-blur": [
            scalar("radius", "Radius (pixels)", 0, 250, 10),
            choice("quality", "Quality", ["Low", "Medium", "High"], 1),
            choice("edges", "Edge handling", ["Transparent", "Repeat edge pixels"], 1),
        ],
        "sharpen": [
            scalar("amount", "Amount", 0, 5, 1),
            scalar("radius", "Radius (pixels)", 0.5, 20, 1.5),
        ],
        "vignette": [
            scalar("intensity", "Intensity (negative lightens)", -1, 1, 0.6),
            scalar("radius", "Radius", 0, 1.5, 0.7),
            scalar("softness", "Softness", 0, 1, 0.5),
            vector("center", "Centre (0 to 1)", 0.5, 0.5),
        ],
        // Stage C: motion graphics
        "drop-shadow": dropShadowParameters,
        "glow": glowParameters,
        "gradient-map": gradientMapParameters,
        // Stage D: stylisation
        "rgb-split": [
            vector("redOffset", "Red offset (pixels)", -8, 0),
            vector("blueOffset", "Blue offset (pixels)", 8, 0),
            scalar("intensity", "Intensity", 0, 1, 1),
        ],
        "pixelate": [
            scalar("blockSize", "Block size (pixels)", 1, 200, 12),
        ],
        "posterize": [
            scalar("levels", "Levels", 2, 32, 6),
        ],
        // Stage E: advanced basics
        "directional-blur": [
            scalar("angle", "Angle (degrees)", -360, 360, 0),
            scalar("distance", "Distance (pixels)", 0, 500, 30),
        ],
        "wave-warp": [
            scalar("amplitude", "Amplitude (pixels)", 0, 500, 20),
            scalar("frequency", "Waves per 1000 pixels", 0, 50, 4),
            scalar("phase", "Phase (degrees)", -360, 360, 0),
            scalar("direction", "Direction (degrees)", -360, 360, 0),
            choice("waveType", "Wave type", ["Sine", "Triangle", "Square"], 0),
        ],
        // Designed, not yet implemented
        "displacement-map": [
            scalar("horizontal", "Horizontal displacement", -500, 500, 20),
            scalar("vertical", "Vertical displacement", -500, 500, 20),
            choice("edges", "Edge handling", ["Transparent", "Repeat edge pixels", "Wrap around"]),
        ],
        "chroma-key": [
            scalar("keyRed", "Key colour red", 0, 1, 0),
            scalar("keyGreen", "Key colour green", 0, 1, 1),
            scalar("keyBlue", "Key colour blue", 0, 1, 0),
            scalar("tolerance", "Tolerance", 0, 1, 0.3),
            scalar("edgeSoftness", "Edge softness", 0, 1, 0.1),
            scalar("spillSuppression", "Spill suppression", 0, 1, 0.5),
        ],
        "motion-blur": [
            scalar("shutterAngle", "Shutter angle (degrees)", 0, 720, 180),
            scalar("samples", "Samples", 2, 64, 16),
            choice("quality", "Quality", ["Draft", "Standard", "High"], 1),
        ],
        "box-blur": [
            scalar("radius", "Radius (pixels)", 0, 100, 8),
            choice("edgeMode", "Edge handling", ["Repeat edge pixels", "Transparent"], 0),
        ],
        "zoom-blur": [
            scalar("amount", "Amount (pixels)", 0, 120, 30),
            vector("center", "Centre (0 to 1)", 0.5, 0.5),
        ],
        "noise": [
            scalar("amount", "Amount", 0, 1, 0.12),
            choice("monochrome", "Noise type", ["Colour", "Monochrome"], 1),
            scalar("seed", "Seed", 0, 10000, 1),
        ],
        "cmyk-halftone-dots": [
            scalar("dotSize", "Dot size (pixels)", 2, 80, 12),
            scalar("contrast", "Contrast", 0.1, 3, 1),
            scalar("angle", "Angle (degrees)", -180, 180, 45),
        ],
        "roughen-edges": [
            scalar("amount", "Edge roughness", 0, 1, 0.35),
            scalar("scale", "Detail scale", 1, 100, 18),
            scalar("softness", "Edge softness", 0, 1, 0.15),
        ],
        "random-displacement": [
            scalar("horizontal", "Horizontal displacement (pixels)", 0, 200, 20),
            scalar("vertical", "Vertical displacement (pixels)", 0, 200, 20),
            scalar("scale", "Noise scale", 1, 200, 40),
            scalar("seed", "Seed", 0, 10000, 1),
        ],
    ]
}
