import SwiftUI
import MotionCore

/// Draws the speed curve of a keyframe's easing: how far through the change you are (up)
/// against how far through the time (across). A straight diagonal means constant speed.
struct EasingCurveView: View {
    let interpolation: Interpolation

    var body: some View {
        Canvas { context, size in
            let steps = 60
            let values: [Double] = (0...steps).map { index in
                curveValue(at: Double(index) / Double(steps))
            }
            let low = min(0, values.min() ?? 0)
            let high = max(1, values.max() ?? 1)
            let padding: CGFloat = 10

            func point(_ x: Double, _ y: Double) -> CGPoint {
                let width = size.width - 2 * padding
                let height = size.height - 2 * padding
                return CGPoint(x: padding + CGFloat(x) * width,
                               y: size.height - padding - CGFloat((y - low) / (high - low)) * height)
            }

            // Guide lines at the start value (0) and the end value (1).
            var guides = Path()
            guides.move(to: point(0, 0))
            guides.addLine(to: point(1, 0))
            guides.move(to: point(0, 1))
            guides.addLine(to: point(1, 1))
            context.stroke(guides, with: .color(Theme.hairline), lineWidth: 1)

            var curve = Path()
            if case .hold = interpolation {
                curve.move(to: point(0, 0))
                curve.addLine(to: point(1, 0))
                curve.addLine(to: point(1, 1))
            } else {
                curve.move(to: point(0, values[0]))
                for index in 1...steps {
                    curve.addLine(to: point(Double(index) / Double(steps), values[index]))
                }
            }
            context.stroke(curve, with: .color(Theme.keyframe),
                           style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
        .frame(height: 96)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel("Easing curve")
    }

    private func curveValue(at x: Double) -> Double {
        switch interpolation {
        case .linear: return x
        case .hold: return 0
        case .bezier(let ease): return ease.solve(x)
        }
    }
}
