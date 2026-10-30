import SwiftUI
import UIKit
import MotionCore

/// The composition preview. Draws the current frame, and lets you tap to select a layer
/// and drag to move it.
@MainActor
struct PreviewView: View {
    let model: EditorModel
    let showAlignmentGuides: Bool

    private struct DragSession {
        var layerID: UUID
        var startPoint: Vec2      // composition pixels
        var startPosition: Vec2
    }

    @State private var session: DragSession?
    @State private var sessionStarted = false
    @State private var verticalGuidePosition: Double?
    @State private var horizontalGuidePosition: Double?
    @State private var scalingStart: (layerID: UUID, scale: Vec2)?

    var body: some View {
        GeometryReader { geometry in
            // Everything the drawing needs is read here, so SwiftUI redraws when any of it changes.
            let composition = model.composition
            let frame = model.resolvedFrame
            let selected = model.selectedLayerID
            // Pictures (and their effects) are prepared in the background. Reading `version` makes the
            // preview redraw when one finishes.
            let _ = model.images.version
            let _ = model.previewCacheVersion
            let cachedSnapshot = model.cachedPreviewImage(at: frame.frameIndex, allowDiskRead: !model.isPlaying)
            let images = cachedSnapshot == nil ? model.images.provideAll(for: frame, playbackPreview: model.isPlaying) : [:]
            let viewport = Viewport(compWidth: Double(composition.width),
                                    compHeight: Double(composition.height),
                                    viewWidth: Double(geometry.size.width),
                                    viewHeight: Double(geometry.size.height))
            ZStack {
                Canvas { context, _ in
                    if let cachedSnapshot {
                        CanvasRenderer.drawCachedSnapshot(cachedSnapshot, frame: frame,
                                                          selectedLayerID: selected, viewport: viewport,
                                                          context: context)
                    } else {
                        CanvasRenderer.draw(frame: frame, selectedLayerID: selected,
                                            viewport: viewport, context: context, images: images)
                    }
                }
                Canvas { context, _ in
                    drawAlignmentGuides(in: &context, viewport: viewport)
                }
                .allowsHitTesting(false)
                if let selectedLayer = frame.layers.first(where: { $0.id == selected }),
                   let selectedModelLayer = model.composition.layer(withID: selectedLayer.id) {
                    scaleHandle(layer: selectedLayer, modelLayer: selectedModelLayer, viewport: viewport)
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(viewport: viewport, frame: frame, compositionWidth: composition.width,
                                 compositionHeight: composition.height))
            .accessibilityElement()
            .accessibilityLabel("Composition preview")
            .accessibilityHint("Drag a layer to move it.")
        }
    }

    private func scaleHandle(layer: ResolvedLayer, modelLayer: Layer, viewport: Viewport) -> some View {
        let corner = viewport.compToView(layer.transform.applying(to: Vec2(x: layer.size.x, y: layer.size.y))).point
        return Circle()
            .fill(.white)
            .frame(width: 14, height: 14)
            .overlay(Circle().stroke(Theme.accent, lineWidth: 2))
            .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
            .position(corner)
            .contentShape(Rectangle().inset(by: -10))
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        if scalingStart?.layerID != layer.id {
                            guard let initialScale = modelLayer.vectorValue(.scale, at: model.currentTime) else { return }
                            scalingStart = (layer.id, initialScale)
                        }
                        guard let startScale = scalingStart?.scale else { return }
                        let base = max(24, (layer.size.x * abs(startScale.x) + layer.size.y * abs(startScale.y)) * viewport.scale)
                        let factor = max(0.05, 1 + (value.translation.width + value.translation.height) / max(base, 1))
                        let scaledX = startScale.x * factor
                        let scaledY = startScale.y * factor
                        model.setVector(.scale, of: layer.id,
                                        to: Vec2(x: scaledX < 0 ? min(-0.01, scaledX) : max(0.01, scaledX),
                                                 y: scaledY < 0 ? min(-0.01, scaledY) : max(0.01, scaledY)),
                                        coalescing: true)
                    }
                    .onEnded { _ in
                        model.endEditGroup()
                        scalingStart = nil
                    }
            )
            .accessibilityLabel("Resize selected layer")
            .accessibilityHint("Drag to scale the selected layer proportionally.")
    }

    private func dragGesture(viewport: Viewport, frame: ResolvedFrame,
                             compositionWidth: Int, compositionHeight: Int) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !sessionStarted {
                    sessionStarted = true
                    let start = viewport.viewToComp(Vec2(x: Double(value.startLocation.x),
                                                         y: Double(value.startLocation.y)))
                    if let hit = Evaluator.hitTest(frame, at: start) {
                        model.select(hit)
                        let position = model.composition.layer(withID: hit)?
                            .vectorValue(.position, at: model.currentTime) ?? .zero
                        session = DragSession(layerID: hit, startPoint: start, startPosition: position)
                    } else {
                        session = nil
                    }
                }
                guard let session else { return }
                // A tap must not move anything: wait until the finger has really moved.
                let travelled = hypot(value.translation.width, value.translation.height)
                guard travelled > 4 else { return }
                let now = viewport.viewToComp(Vec2(x: Double(value.location.x), y: Double(value.location.y)))
                var target = session.startPosition + (now - session.startPoint)
                let threshold = 10.0 / max(viewport.scale, 0.001)
                if showAlignmentGuides,
                   let movingLayer = frame.layers.first(where: { $0.id == session.layerID }) {
                    // Bounds are calculated from the transformed corners, so rotated and scaled
                    // layers snap by their visible edges rather than only by their anchor point.
                    let currentPosition = model.composition.layer(withID: session.layerID)?
                        .vectorValue(.position, at: model.currentTime) ?? session.startPosition
                    let offset = target - currentPosition
                    let movingBounds = bounds(of: movingLayer, offset: offset)
                    let otherBounds = frame.layers
                        .filter { $0.id != session.layerID && isGuideEligible($0) }
                        .map { bounds(of: $0, offset: .zero) }
                    let xTargets = [0.0, Double(compositionWidth) / 2, Double(compositionWidth)] +
                        otherBounds.flatMap { [$0.minX, $0.midX, $0.maxX] }
                    let yTargets = [0.0, Double(compositionHeight) / 2, Double(compositionHeight)] +
                        otherBounds.flatMap { [$0.minY, $0.midY, $0.maxY] }
                    let xSnap = closestSnap(features: [movingBounds.minX, movingBounds.midX, movingBounds.maxX],
                                            targets: xTargets, threshold: threshold)
                    let ySnap = closestSnap(features: [movingBounds.minY, movingBounds.midY, movingBounds.maxY],
                                            targets: yTargets, threshold: threshold)
                    if let xSnap { target.x += xSnap.delta }
                    if let ySnap { target.y += ySnap.delta }
                    if (xSnap?.target != verticalGuidePosition) || (ySnap?.target != horizontalGuidePosition) {
                        if xSnap != nil || ySnap != nil { MotionStudioHaptics.impact(.light) }
                    }
                    verticalGuidePosition = xSnap?.target
                    horizontalGuidePosition = ySnap?.target
                } else {
                    verticalGuidePosition = nil
                    horizontalGuidePosition = nil
                }
                model.movePosition(of: session.layerID, to: target)
            }
            .onEnded { _ in
                if session == nil {
                    model.select(nil)   // a tap on empty space clears the selection
                } else {
                    model.endEditGroup()
                }
                session = nil
                sessionStarted = false
                verticalGuidePosition = nil
                horizontalGuidePosition = nil
            }
    }

    private struct LayerBounds {
        var minX: Double
        var midX: Double
        var maxX: Double
        var minY: Double
        var midY: Double
        var maxY: Double
    }

    private struct SnapMatch: Equatable {
        var delta: Double
        var target: Double
    }

    private func isGuideEligible(_ layer: ResolvedLayer) -> Bool {
        switch layer.kind {
        case .audio, .null, .adjustment: return false
        default: return true
        }
    }

    private func bounds(of layer: ResolvedLayer, offset: Vec2) -> LayerBounds {
        let corners = [
            Vec2(x: 0, y: 0), Vec2(x: layer.size.x, y: 0),
            Vec2(x: 0, y: layer.size.y), Vec2(x: layer.size.x, y: layer.size.y)
        ].map { layer.transform.applying(to: $0) + offset }
        let xs = corners.map(\.x)
        let ys = corners.map(\.y)
        let minX = xs.min() ?? 0, maxX = xs.max() ?? 0
        let minY = ys.min() ?? 0, maxY = ys.max() ?? 0
        return LayerBounds(minX: minX, midX: (minX + maxX) / 2, maxX: maxX,
                           minY: minY, midY: (minY + maxY) / 2, maxY: maxY)
    }

    private func closestSnap(features: [Double], targets: [Double], threshold: Double) -> SnapMatch? {
        var best: SnapMatch?
        for feature in features {
            for target in targets {
                let delta = target - feature
                guard abs(delta) <= threshold else { continue }
                if best == nil || abs(delta) < abs(best!.delta) {
                    best = SnapMatch(delta: delta, target: target)
                }
            }
        }
        return best
    }

    private func drawAlignmentGuides(in context: inout GraphicsContext, viewport: Viewport) {
        guard showAlignmentGuides else { return }
        let origin = viewport.origin
        let width = viewport.compWidth * viewport.scale
        let height = viewport.compHeight * viewport.scale
        let frame = CGRect(x: origin.x, y: origin.y, width: width, height: height)

        // Persistent thirds grid and safe-area frame.
        var grid = Path()
        for fraction in [1.0 / 3.0, 2.0 / 3.0] {
            let x = origin.x + width * fraction
            let y = origin.y + height * fraction
            grid.move(to: CGPoint(x: x, y: origin.y))
            grid.addLine(to: CGPoint(x: x, y: origin.y + height))
            grid.move(to: CGPoint(x: origin.x, y: y))
            grid.addLine(to: CGPoint(x: origin.x + width, y: y))
        }
        context.stroke(grid, with: .color(Theme.textSecondary.opacity(0.28)),
                       style: StrokeStyle(lineWidth: 0.7, dash: [3, 5]))
        let safe = CGRect(x: origin.x + width * 0.05, y: origin.y + height * 0.05,
                          width: width * 0.9, height: height * 0.9)
        context.stroke(Path(safe), with: .color(Theme.accent.opacity(0.45)),
                       style: StrokeStyle(lineWidth: 0.8, dash: [4, 4]))

        // Live guides show the exact line the moving layer has snapped to: canvas borders,
        // canvas centre, or an edge/centre of another visible layer.
        var snap = Path()
        if let x = verticalGuidePosition {
            let viewX = origin.x + x * viewport.scale
            snap.move(to: CGPoint(x: viewX, y: frame.minY))
            snap.addLine(to: CGPoint(x: viewX, y: frame.maxY))
        }
        if let y = horizontalGuidePosition {
            let viewY = origin.y + y * viewport.scale
            snap.move(to: CGPoint(x: frame.minX, y: viewY))
            snap.addLine(to: CGPoint(x: frame.maxX, y: viewY))
        }
        context.stroke(snap, with: .color(Theme.accent),
                       style: StrokeStyle(lineWidth: 1.6, dash: [6, 3]))
    }

}
