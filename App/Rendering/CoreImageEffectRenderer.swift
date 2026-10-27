import CoreImage
import CoreGraphics
import Foundation
import MotionCore

/// Hardware-accelerated fast path for common effects used during preview and export.
/// Core Image builds one filter graph and renders it once, avoiding the CPU PixelImage
/// float-array conversion for these effects. Unsupported/mixed stacks use EffectPipeline.
enum CoreImageEffectRenderer {
    // CIContext is thread-safe and expensive to create. The default context uses the best
    // available render device (normally Metal on supported iOS devices).
    private static let context = CIContext(options: [.cacheIntermediates: false])
    private static let supported: Set<String> = [
        "brightness-contrast", "hue-shift", "saturation-vibrance", "invert",
        "gaussian-blur", "sharpen"
    ]

    static func canRender(_ effects: [ResolvedEffect]) -> Bool {
        !effects.isEmpty && effects.allSatisfy { supported.contains($0.effectID) }
    }

    static func render(_ image: CGImage, effects: [ResolvedEffect], scale: Double) -> CGImage? {
        guard canRender(effects), scale.isFinite, scale > 0 else { return nil }
        let original = CIImage(cgImage: image)
        let extent = original.extent
        var current = original
        var didChange = false

        for effect in effects {
            let values = EffectValues(resolved: effect)
            let filter: CIFilter
            switch effect.effectID {
            case "brightness-contrast":
                let brightness = values.scalar("brightness")
                let contrast = values.scalar("contrast")
                guard brightness != 0 || contrast != 0 else { continue }
                filter = CIFilter(name: "CIColorControls")!
                filter.setValue(current, forKey: kCIInputImageKey)
                filter.setValue(brightness, forKey: kCIInputBrightnessKey)
                // Keep Motion Studio's existing contrast convention: -1...1 maps to 0.25...4.
                filter.setValue(pow(2.0, contrast * 2.0), forKey: kCIInputContrastKey)
                filter.setValue(1.0, forKey: kCIInputSaturationKey)

            case "hue-shift":
                let degrees = values.scalar("degrees")
                guard degrees != 0 else { continue }
                filter = CIFilter(name: "CIHueAdjust")!
                filter.setValue(current, forKey: kCIInputImageKey)
                filter.setValue(degrees * .pi / 180.0, forKey: kCIInputAngleKey)

            case "saturation-vibrance":
                let saturation = values.scalar("saturation")
                guard saturation != 1 else { continue }
                filter = CIFilter(name: "CIColorControls")!
                filter.setValue(current, forKey: kCIInputImageKey)
                filter.setValue(saturation, forKey: kCIInputSaturationKey)
                filter.setValue(1.0, forKey: kCIInputContrastKey)
                filter.setValue(0.0, forKey: kCIInputBrightnessKey)

            case "invert":
                filter = CIFilter(name: "CIColorInvert")!
                filter.setValue(current, forKey: kCIInputImageKey)

            case "gaussian-blur":
                let radius = values.scalar("radius") * scale
                guard radius >= 0.3 else { continue }
                filter = CIFilter(name: "CIGaussianBlur")!
                let edgeMode = values.choice("edges")
                let input = edgeMode != 0 ? current.clampedToExtent() : current
                filter.setValue(input, forKey: kCIInputImageKey)
                filter.setValue(radius, forKey: kCIInputRadiusKey)

            case "sharpen":
                let amount = values.scalar("amount")
                guard amount > 0 else { continue }
                filter = CIFilter(name: "CISharpenLuminance")!
                filter.setValue(current, forKey: kCIInputImageKey)
                filter.setValue(amount, forKey: kCIInputSharpnessKey)
                filter.setValue(values.scalar("radius") * scale, forKey: kCIInputRadiusKey)

            default:
                return nil
            }
            guard let output = filter.outputImage else { return nil }
            // These effects do not expand the layer bounds. Crop blur's expanded extent back to
            // the original bitmap so its geometry stays consistent with the CPU implementation.
            current = output.cropped(to: extent)
            didChange = true
        }

        guard didChange else { return image }
        return context.createCGImage(current, from: extent, format: .RGBA8,
                                     colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    }
}
