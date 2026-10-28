import SwiftUI
import UIKit
import MotionCore

/// Draws a resolved composition frame with SwiftUI Canvas. Animated motion-blur samples
/// are supplied by MotionCore's evaluator so preview and export use the same transforms.
enum CanvasRenderer {

    static func draw(frame: ResolvedFrame,
                     selectedLayerID: UUID?,
                     viewport: Viewport,
                     context: GraphicsContext,
                     images: [UUID: ProvidedImage] = [:]) {
        let scale = viewport.scale
        let origin = viewport.origin
        let compRect = CGRect(x: origin.x, y: origin.y,
                              width: Double(frame.width) * scale,
                              height: Double(frame.height) * scale)

        var base = context
        base.fill(Path(compRect), with: .color(frame.background.color))
        base.clip(to: Path(compRect))

        let compToView = viewport.compToViewTransform
        for layer in frame.layers {
            // Draw temporal samples first, then the sharp current frame. This makes Motion Blur
            // follow animated transforms on image, video, text and shape layers.
            if !layer.motionBlurTransforms.isEmpty {
                for sampledTransform in layer.motionBlurTransforms {
                    var trail = base
                    trail.opacity = layer.opacity * layer.motionBlurTrailOpacity
                    trail.blendMode = layer.blendMode.graphicsBlendMode
                    trail.concatenate(compToView.concatenating(sampledTransform).cgAffine)
                    drawLayerBody(layer, in: &trail, rect: CGRect(x: 0, y: 0, width: layer.size.x, height: layer.size.y),
                                  provided: images[layer.id])
                }
            }
            var layerContext = base
            layerContext.opacity = layer.opacity
            layerContext.blendMode = layer.blendMode.graphicsBlendMode
            layerContext.concatenate(compToView.concatenating(layer.transform).cgAffine)
            let rect = CGRect(x: 0, y: 0, width: layer.size.x, height: layer.size.y)
            drawLayerBody(layer, in: &layerContext, rect: rect, provided: images[layer.id])
        }

        context.stroke(Path(compRect), with: .color(Theme.hairline), lineWidth: 1)
        drawSelection(frame: frame, selectedLayerID: selectedLayerID, viewport: viewport, context: context)
    }

    /// Draws a previously rendered, low-resolution composition frame and overlays live selection UI.
    /// The cached image contains no selection handles or guides, so those remain responsive while playing.
    static func drawCachedSnapshot(_ image: CGImage,
                                   frame: ResolvedFrame,
                                   selectedLayerID: UUID?,
                                   viewport: Viewport,
                                   context: GraphicsContext) {
        let rect = CGRect(x: viewport.origin.x, y: viewport.origin.y,
                          width: Double(frame.width) * viewport.scale,
                          height: Double(frame.height) * viewport.scale)
        context.fill(Path(rect), with: .color(frame.background.color))
        context.clip(to: Path(rect))
        let resolved = context.resolve(Image(decorative: image, scale: 1))
        context.draw(resolved, in: rect)
        context.stroke(Path(rect), with: .color(Theme.hairline), lineWidth: 1)
        drawSelection(frame: frame, selectedLayerID: selectedLayerID, viewport: viewport, context: context)
    }

    /// An imported picture, after its effects. While the picture is still loading, or if its file is missing,
    /// a plain placeholder is drawn instead (never a fake effect).
    private static func drawLayerBody(_ layer: ResolvedLayer, in context: inout GraphicsContext,
                                      rect: CGRect, provided: ProvidedImage?) {
        switch layer.kind {
        case .image, .video:
            drawImageLayer(layer, rect: rect, provided: provided, in: &context)
        case .solid, .shape, .text:
            if EffectPipeline.hasWork(layer.effects), let rendered = VectorLayerEffectRenderer.renderIfNeeded(layer) {
                let image = context.resolve(Image(decorative: rendered.image, scale: 1))
                context.draw(image, in: rendered.rect)
            } else {
                drawVectorBody(layer, in: &context, rect: rect)
            }
        case .audio, .null, .adjustment:
            break
        default:
            drawVectorBody(layer, in: &context, rect: rect)
        }
    }

    private static func drawVectorBody(_ layer: ResolvedLayer, in context: inout GraphicsContext, rect: CGRect) {
        switch layer.kind {
        case .text(let content):
            let size = max(12, rect.height * 0.7)
            let text: Text
            if let fontName = layer.textFontName, !fontName.isEmpty {
                text = Text(content).font(.custom(fontName, size: size)).foregroundColor(layer.fill.color)
            } else {
                text = Text(content).font(.system(size: size, weight: .medium)).foregroundColor(layer.fill.color)
            }
            context.draw(context.resolve(text), at: CGPoint(x: rect.minX, y: rect.midY), anchor: .leading)
        case .shape(.ellipse):
            context.fill(Path(ellipseIn: rect), with: .color(layer.fill.color))
        case .solid, .shape(.rectangle):
            context.fill(Path(rect), with: .color(layer.fill.color))
        default:
            break
        }
    }

    private static func drawImageLayer(_ layer: ResolvedLayer, rect: CGRect, provided: ProvidedImage?,
                                       in context: inout GraphicsContext) {
        switch provided ?? .missing {
        case .ready(let image, let drawRect):
            let resolved = context.resolve(Image(decorative: image, scale: 1))
            context.draw(resolved, in: drawRect)
        case .loading:
            context.fill(Path(rect), with: .color(Color.gray.opacity(0.25)))
        case .missing:
            context.fill(Path(rect), with: .color(Color.gray.opacity(0.35)))
            var cross = Path()
            cross.move(to: CGPoint(x: rect.minX, y: rect.minY))
            cross.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            cross.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            cross.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            context.stroke(cross, with: .color(Color.white.opacity(0.5)), lineWidth: max(2, rect.width / 200))
        }
    }

    /// An outline around the selected layer, following its rotation and scale.
    static func drawSelection(frame: ResolvedFrame,
                                      selectedLayerID: UUID?,
                                      viewport: Viewport,
                                      context: GraphicsContext) {
        guard let id = selectedLayerID,
              let layer = frame.layers.first(where: { $0.id == id }) else { return }
        let corners = [Vec2(0, 0), Vec2(layer.size.x, 0), Vec2(layer.size.x, layer.size.y), Vec2(0, layer.size.y)]
            .map { viewport.compToView(layer.transform.applying(to: $0)).point }
        var outline = Path()
        outline.move(to: corners[0])
        for corner in corners.dropFirst() {
            outline.addLine(to: corner)
        }
        outline.closeSubpath()
        context.stroke(outline, with: .color(Theme.accent),
                       style: StrokeStyle(lineWidth: 2, lineJoin: .round))
    }
}

extension MotionCore.BlendMode {
    var graphicsBlendMode: GraphicsContext.BlendMode {
        switch self {
        case .normal: return .normal
        case .add: return .plusLighter
        case .multiply: return .multiply
        case .screen: return .screen
        }
    }
}
