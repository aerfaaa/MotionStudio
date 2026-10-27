import SwiftUI
import MotionCore

/// The V1 preview renderer. It draws a `ResolvedFrame` with SwiftUI's Canvas.
///
/// It knows nothing about keyframes, undo or files. It only draws the finished values it is given.
/// The future Metal renderer and the video exporter will read the same `ResolvedFrame`.
///
/// V1 limits: solid and shape layers only, blend modes via the Canvas, no effects.
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
            var layerContext = base
            layerContext.opacity = layer.opacity
            layerContext.blendMode = layer.blendMode.graphicsBlendMode
            // Layer pixels -> composition pixels -> screen points, in one step.
            layerContext.concatenate(compToView.concatenating(layer.transform).cgAffine)

            let rect = CGRect(x: 0, y: 0, width: layer.size.x, height: layer.size.y)
            if case .image = layer.kind {
                drawImageLayer(layer, rect: rect, provided: images[layer.id], in: &layerContext)
                continue
            }
            let path: Path
            if case .shape(.ellipse) = layer.kind {
                path = Path(ellipseIn: rect)
            } else {
                path = Path(rect)
            }
            layerContext.fill(path, with: .color(layer.fill.color))
        }

        context.stroke(Path(compRect), with: .color(Theme.hairline), lineWidth: 1)
        drawSelection(frame: frame, selectedLayerID: selectedLayerID, viewport: viewport, context: context)
    }

    /// An imported picture, after its effects. While the picture is still loading, or if its file is missing,
    /// a plain placeholder is drawn instead (never a fake effect).
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
    private static func drawSelection(frame: ResolvedFrame,
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
