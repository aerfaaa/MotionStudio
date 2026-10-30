import SwiftUI

/// Compact, tactile value control: drag the tick ruler for fine adjustments or type a number directly.
struct RulerValueControl: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0.01
    var suffix: String = ""
    @State private var dragOrigin: Double?

    var body: some View {
        HStack(spacing: 10) {
            GeometryReader { geometry in
                ZStack {
                    RoundedRectangle(cornerRadius: 9).fill(Theme.surfaceRaised)
                    Canvas { context, size in
                        let mid = size.width / 2
                        let spacing: CGFloat = 8
                        for i in -Int(size.width / spacing / 2)...Int(size.width / spacing / 2) {
                            let major = i % 5 == 0
                            var tick = Path()
                            tick.move(to: CGPoint(x: mid + CGFloat(i) * spacing, y: major ? 5 : 11))
                            tick.addLine(to: CGPoint(x: mid + CGFloat(i) * spacing, y: size.height - 5))
                            context.stroke(tick, with: .color(Theme.textSecondary.opacity(major ? 0.75 : 0.35)), lineWidth: major ? 1.2 : 0.7)
                        }
                    }
                    Capsule().fill(Theme.accent).frame(width: 2, height: 26)
                }
                .contentShape(RoundedRectangle(cornerRadius: 9))
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if dragOrigin == nil { dragOrigin = value }
                        guard let start = dragOrigin else { return }
                        let fraction = Double(gesture.translation.width / max(geometry.size.width, 1))
                        let raw = start + fraction * (range.upperBound - range.lowerBound)
                        value = min(range.upperBound, max(range.lowerBound, (raw / max(step, 0.000001)).rounded() * step))
                    }
                    .onEnded { _ in dragOrigin = nil })
                .accessibilityLabel("Fine adjustment ruler")
                .accessibilityHint("Drag horizontally to adjust the value.")
            }
            .frame(height: 34)

            HStack(spacing: 3) {
                TextField("Value", value: $value, format: .number.precision(.fractionLength(0...3)))
                    .keyboardType(.numbersAndPunctuation)
                    .multilineTextAlignment(.trailing)
                    .font(.system(.subheadline, design: .monospaced))
                    .frame(minWidth: 42, maxWidth: 62)
                    .onChange(of: value) { _, newValue in
                        if newValue.isFinite { value = min(range.upperBound, max(range.lowerBound, newValue)) }
                    }
                if !suffix.isEmpty {
                    Text(suffix).font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.horizontal, 7)
            .frame(height: 34)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.hairline, lineWidth: 1))
        }
    }
}
