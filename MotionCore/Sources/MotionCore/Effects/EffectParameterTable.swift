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

    static let parameters: [String: [EffectParameterDefinition]] = [
        "gaussian-blur": [
            scalar("radius", "Radius", 0, 250, 10),
            choice("quality", "Quality", ["Low", "Medium", "High"], 1),
            choice("edges", "Edge handling", ["Transparent", "Repeat edge pixels"]),
        ],
        "brightness-contrast": [
            scalar("brightness", "Brightness", -1, 1, 0),
            scalar("contrast", "Contrast", -1, 1, 0),
        ],
        "hue-shift": [
            scalar("degrees", "Hue shift (degrees)", -180, 180, 0),
        ],
        "glow": [
            scalar("threshold", "Threshold", 0, 1, 0.6),
            scalar("radius", "Radius", 0, 200, 30),
            scalar("intensity", "Intensity", 0, 4, 1),
            scalar("colorRed", "Colour red", 0, 1, 1),
            scalar("colorGreen", "Colour green", 0, 1, 1),
            scalar("colorBlue", "Colour blue", 0, 1, 1),
        ],
        "rgb-split": [
            vector("redOffset", "Red offset", -8, 0),
            vector("blueOffset", "Blue offset", 8, 0),
            scalar("intensity", "Intensity", 0, 1, 1),
        ],
        "displacement-map": [
            scalar("horizontal", "Horizontal displacement", -500, 500, 20),
            scalar("vertical", "Vertical displacement", -500, 500, 20),
            choice("edges", "Edge handling", ["Transparent", "Repeat edge pixels", "Wrap around"]),
        ],
        "wave-warp": [
            scalar("amplitude", "Amplitude", 0, 500, 20),
            scalar("frequency", "Frequency", 0, 50, 4),
            scalar("phase", "Phase (degrees)", -360, 360, 0),
            scalar("direction", "Direction (degrees)", -360, 360, 0),
            choice("waveType", "Wave type", ["Sine", "Triangle", "Square"]),
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
    ]
}
