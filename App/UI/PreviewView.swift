import SwiftUI
import MotionCore

/// The composition preview. Draws the current frame, and lets you tap to select a layer
/// and drag to move it.
@MainActor
struct PreviewView: View {
    let model: EditorModel

    private struct DragSession {
        var layerID: UUID
        var startPoint: Vec2      // composition pixels
        var startPosition: Vec2
    }

    @State private var session: DragSession?
    @State private var sessionStarted = false

    var body: some View {
        GeometryReader { geometry in
            // Everything the drawing needs is read here, so SwiftUI redraws when any of it changes.
            let composition = model.composition
            let frame = model.resolvedFrame
            let selected = model.selectedLayerID
            let viewport = Viewport(compWidth: Double(composition.width),
                                    compHeight: Double(composition.height),
                                    viewWidth: Double(geometry.size.width),
                                    viewHeight: Double(geometry.size.height))
            Canvas { context, _ in
                CanvasRenderer.draw(frame: frame, selectedLayerID: selected,
                                    viewport: viewport, context: context)
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(viewport: viewport, frame: frame))
            .accessibilityElement()
            .accessibilityLabel("Composition preview")
            .accessibilityHint("Drag a layer to move it.")
        }
    }

    private func dragGesture(viewport: Viewport, frame: ResolvedFrame) -> some Gesture {
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
                model.movePosition(of: session.layerID, to: session.startPosition + (now - session.startPoint))
            }
            .onEnded { _ in
                if session == nil {
                    model.select(nil)   // a tap on empty space clears the selection
                } else {
                    model.endEditGroup()
                }
                session = nil
                sessionStarted = false
            }
    }
}
