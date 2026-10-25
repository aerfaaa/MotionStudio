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
                     context: GraphicsContext) {
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
