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

    var body: some View {
        GeometryReader { geometry in
            // Everything the drawing needs is read here, so SwiftUI redraws when any of it changes.
            let composition = model.composition
            let frame = model.resolvedFrame
            let selected = model.selectedLayerID
            // Pictures (and their effects) are prepared in the background. Reading `version` makes the
            // preview redraw when one finishes.
            let _ = model.images.version
            let images = model.images.provideAll(for: frame)
            let viewport = Viewport(compWidth: Double(composition.width),
                                    compHeight: Double(composition.height),
                                    viewWidth: Double(geometry.size.width),
                                    viewHeight: Double(geometry.size.height))
            Canvas { context, _ in
                CanvasRenderer.draw(frame: frame, selectedLayerID: selected,
                                    viewport: viewport, context: context, images: images)
                drawAlignmentGuides(in: &context, viewport: viewport)
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(viewport: viewport, frame: frame, compositionWidth: composition.width,
                                 compositionHeight: composition.height))
            .accessibilityElement()
            .accessibilityLabel("Composition preview")
            .accessibilityHint("Drag a layer to move it.")
        }
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
        guard showAlignmentGuides, showingVerticalGuide || showingHorizontalGuide else { return }
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
        context.stroke(path, with: .color(Theme.accent), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
    }
}
