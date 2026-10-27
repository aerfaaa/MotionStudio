import CoreGraphics
import Foundation
import UIKit
import MotionCore

/// Rasterizes vector layers only when they have active effects. Results are cached by the full
/// visual input, so dragging or scrubbing does not repeatedly rasterize an unchanged shape.
enum VectorLayerEffectRenderer {
    struct Result {
        let image: CGImage
        /// The image's top-left offset in layer-local coordinates (effects such as shadows can expand it).
        let rect: CGRect
    }

    private final class Box: NSObject {
        let result: Result
        init(_ result: Result) { self.result = result }
    }

    private static let cache: NSCache<NSString, Box> = {
        let value = NSCache<NSString, Box>()
        value.countLimit = 48
        value.totalCostLimit = 96 * 1024 * 1024
        return value
    }()

    static func renderIfNeeded(_ layer: ResolvedLayer) -> Result? {
        guard EffectPipeline.hasWork(layer.effects), layer.size.x > 0, layer.size.y > 0 else { return nil }
        switch layer.kind {
        case .solid, .shape, .text: break
        default: return nil
        }
        let key = signature(for: layer) as NSString
        if let hit = cache.object(forKey: key) { return hit.result }
        guard let source = rasterize(layer) else { return nil }
        let scale = Double(source.width) / max(layer.size.x, 1)
        let output: CGImage
        let outputRect: CGRect
        if CoreImageEffectRenderer.canRender(layer.effects),
           let accelerated = CoreImageEffectRenderer.render(source, effects: layer.effects, scale: scale) {
            output = accelerated
            outputRect = CGRect(x: 0, y: 0, width: layer.size.x, height: layer.size.y)
        } else if let pixels = PixelBridge.makePixelImage(from: source) {
            let processed = EffectPipeline.apply(layer.effects, to: pixels, scale: scale)
            guard let cgImage = PixelBridge.makeCGImage(from: processed.image) else { return nil }
            output = cgImage
            outputRect = CGRect(x: Double(processed.image.originX) / scale,
                                y: Double(processed.image.originY) / scale,
                                width: Double(processed.image.width) / scale,
                                height: Double(processed.image.height) / scale)
        } else {
            return nil
        }
        let result = Result(image: output, rect: outputRect)
        cache.setObject(Box(result), forKey: key, cost: output.bytesPerRow * output.height)
        return result
    }

    private static func rasterize(_ layer: ResolvedLayer) -> CGImage? {
        // Cap vector effect rasterization to keep previews responsive on large compositions.
        let scale = min(1.0, 2048.0 / max(max(layer.size.x, layer.size.y), 1.0))
        let width = max(1, Int((layer.size.x * scale).rounded()))
        let height = max(1, Int((layer.size.y * scale).rounded()))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: CGFloat(width), height: CGFloat(height)), format: format)
        let image = renderer.image { rendererContext in
            let context = rendererContext.cgContext
            context.clear(CGRect(x: 0, y: 0, width: width, height: height))
            context.scaleBy(x: CGFloat(width) / CGFloat(layer.size.x), y: CGFloat(height) / CGFloat(layer.size.y))
            let rect = CGRect(x: 0, y: 0, width: CGFloat(layer.size.x), height: CGFloat(layer.size.y))
            let color = UIColor(red: CGFloat(layer.fill.r), green: CGFloat(layer.fill.g), blue: CGFloat(layer.fill.b), alpha: CGFloat(layer.fill.a))
            switch layer.kind {
            case .solid, .shape(.rectangle):
                context.setFillColor(color.cgColor)
                context.fill(rect)
            case .shape(.ellipse):
                context.setFillColor(color.cgColor)
                context.fillEllipse(in: rect)
            case .text(let content):
                let fontSize = max(12, rect.height * 0.7)
                let font = layer.textFontName.flatMap { UIFont(name: $0, size: fontSize) } ?? UIFont.systemFont(ofSize: fontSize, weight: .medium)
                (content as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color])
            default:
                break
            }
        }
        return image.cgImage
    }

    private static func signature(for layer: ResolvedLayer) -> String {
        let kind: String
        switch layer.kind {
        case .solid: kind = "solid"
        case .shape(let shape): kind = "shape-\(shape.rawValue)"
        case .text(let content): kind = "text-\(content)-\(layer.textFontName ?? "system")"
        default: kind = "unsupported"
        }
        let effectSignature = layer.effects.map { effect in
            let values = effect.values.keys.sorted().map { key in
                "\(key)=\(effect.values[key, default: []].map { String(format: "%.5f", $0) }.joined(separator: ","))"
            }.joined(separator: ";")
            return "\(effect.effectID){\(values)}"
        }.joined(separator: "|")
        return "\(layer.id.uuidString)|\(kind)|\(layer.size.x)x\(layer.size.y)|\(layer.fill.r),\(layer.fill.g),\(layer.fill.b),\(layer.fill.a)|\(effectSignature)"
    }
}
