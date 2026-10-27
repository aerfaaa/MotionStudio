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
    @State private var showingVerticalGuide = false
    @State private var showingHorizontalGuide = false
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
            let images = model.images.provideAll(for: frame, playbackPreview: model.isPlaying)
            let viewport = Viewport(compWidth: Double(composition.width),
                                    compHeight: Double(composition.height),
                                    viewWidth: Double(geometry.size.width),
                                    viewHeight: Double(geometry.size.height))
            ZStack {
                Canvas { context, _ in
                    CanvasRenderer.draw(frame: frame, selectedLayerID: selected,
                                        viewport: viewport, context: context, images: images)
                    drawAlignmentGuides(in: &context, viewport: viewport)
                }
                .contentShape(Rectangle())
                .gesture(dragGesture(viewport: viewport, frame: frame, compositionWidth: composition.width,
                                     compositionHeight: composition.height))
                if let selectedLayer = frame.layers.first(where: { $0.id == selected }),
                   let selectedModelLayer = model.composition.layer(withID: selectedLayer.id) {
                    scaleHandle(layer: selectedLayer, modelLayer: selectedModelLayer, viewport: viewport)
                }
            }
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
                let snappedX = showAlignmentGuides && abs(target.x - Double(compositionWidth) / 2) <= threshold
                let snappedY = showAlignmentGuides && abs(target.y - Double(compositionHeight) / 2) <= threshold
                if snappedX { target.x = Double(compositionWidth) / 2 }
                if snappedY { target.y = Double(compositionHeight) / 2 }
                if (snappedX && !showingVerticalGuide) || (snappedY && !showingHorizontalGuide) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                showingVerticalGuide = snappedX
                showingHorizontalGuide = snappedY
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
                showingVerticalGuide = false
                showingHorizontalGuide = false
            }
    }

    private func drawAlignmentGuides(in context: inout GraphicsContext, viewport: Viewport) {
        guard showAlignmentGuides else { return }
        let origin = viewport.origin
        let width = viewport.compWidth * viewport.scale
        let height = viewport.compHeight * viewport.scale
        var path = Path()
        if showingVerticalGuide {
            let x = origin.x + width / 2
            path.move(to: CGPoint(x: x, y: origin.y))
            path.addLine(to: CGPoint(x: x, y: origin.y + height))
        }
        if showingHorizontalGuide {
            let y = origin.y + height / 2
            path.move(to: CGPoint(x: origin.x, y: y))
            path.addLine(to: CGPoint(x: origin.x + width, y: y))
        }
        // Thirds and a 5% title-safe frame are visible only while the guide overlay is enabled.
        for fraction in [1.0 / 3.0, 2.0 / 3.0] {
            let x = origin.x + width * fraction
            let y = origin.y + height * fraction
            path.move(to: CGPoint(x: x, y: origin.y))
            path.addLine(to: CGPoint(x: x, y: origin.y + height))
            path.move(to: CGPoint(x: origin.x, y: y))
            path.addLine(to: CGPoint(x: origin.x + width, y: y))
        }
        context.stroke(path, with: .color(Theme.textSecondary.opacity(0.45)), style: StrokeStyle(lineWidth: 0.7, dash: [3, 5]))
        let safe = CGRect(x: origin.x + width * 0.05, y: origin.y + height * 0.05,
                          width: width * 0.9, height: height * 0.9)
        context.stroke(Path(safe), with: .color(Theme.accent.opacity(0.65)), style: StrokeStyle(lineWidth: 0.8, dash: [4, 4]))
        var center = Path()
        center.move(to: CGPoint(x: origin.x + width / 2, y: origin.y))
        center.addLine(to: CGPoint(x: origin.x + width / 2, y: origin.y + height))
        center.move(to: CGPoint(x: origin.x, y: origin.y + height / 2))
        center.addLine(to: CGPoint(x: origin.x + width, y: origin.y + height / 2))
        context.stroke(center, with: .color(Theme.accent.opacity(0.2)), lineWidth: 0.6)
    }
}
