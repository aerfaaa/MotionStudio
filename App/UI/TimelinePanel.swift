import SwiftUI
import MotionCore

/// The timeline: a ruler you can drag to scrub, one row per layer with its in/out bar,
/// and amber diamonds where the layer has keyframes.
/// V1 fits the whole composition to the width. Zooming and trimming come later.
@MainActor
struct TimelinePanel: View {
    let model: EditorModel

    private let rowHeight: CGFloat = 46
    private let rulerHeight: CGFloat = 38

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let labelWidth: CGFloat = width < 420 ? 112 : 176
            let trackWidth: CGFloat = max(1, width - labelWidth)
            let duration = max(model.composition.duration.seconds, 0.001)
            let pointsPerSecond: CGFloat = trackWidth / CGFloat(duration)
            let playheadX: CGFloat = labelWidth + CGFloat(model.currentTime.seconds) * pointsPerSecond

            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Text("\(model.composition.layers.count) layers")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.leading, 14)
                            .frame(width: labelWidth, height: rulerHeight, alignment: .leading)
                        TimelineRuler(duration: duration, pointsPerSecond: pointsPerSecond) { x in
                            model.seek(toSeconds: Double(x / pointsPerSecond))
                        }
                        .frame(height: rulerHeight)
                    }
                    Rectangle().fill(Theme.hairline).frame(height: 1)

                    if model.composition.layers.isEmpty {
                        Spacer()
                        Text("No layers yet. Tap + to add a shape.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity)
                        Spacer()
                    } else {
                        ScrollView(.vertical) {
                            VStack(spacing: 0) {
                                ForEach(model.composition.layers) { layer in
                                    LayerRow(layer: layer,
                                             isSelected: layer.id == model.selectedLayerID,
                                             compositionSeconds: duration,
                                             pointsPerSecond: pointsPerSecond,
                                             labelWidth: labelWidth,
                                             rowHeight: rowHeight,
                                             onSelect: { model.select(layer.id) },
                                             onToggleVisibility: { model.setVisibility(layer.id, to: !layer.isVisible) })
                                }
                            }
                        }
                    }
                }

                // The playhead: a thin line across the ruler and every row.
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: 2)
                    .offset(x: playheadX - 1)
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct TimelineRuler: View {
    let duration: Double
    let pointsPerSecond: CGFloat
    let onScrub: (CGFloat) -> Void

    var body: some View {
        Canvas { context, size in
            let candidates: [Double] = [0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600]
            let step = candidates.first(where: { $0 * Double(pointsPerSecond) >= 56 }) ?? 600
            var seconds = 0.0
            while seconds <= duration + 0.0001 {
                let x = CGFloat(seconds) * pointsPerSecond
                var tick = Path()
                tick.move(to: CGPoint(x: x, y: size.height - 12))
                tick.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(tick, with: .color(Theme.textSecondary.opacity(0.6)), lineWidth: 1)
                let label = Text(TimelineRuler.format(seconds, step: step))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.textSecondary)
                context.draw(label, at: CGPoint(x: x + 4, y: size.height - 24), anchor: .leading)
                seconds += step
            }
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
            onScrub(value.location.x)
        })
        .accessibilityLabel("Timeline ruler")
        .accessibilityHint("Drag to move the playhead.")
    }

    private static func format(_ seconds: Double, step: Double) -> String {
        if step < 1 { return String(format: "%.1fs", seconds) }
        let whole = Int(seconds.rounded())
        if whole < 60 { return "\(whole)s" }
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}

private struct LayerRow: View {
    let layer: Layer
    let isSelected: Bool
    let compositionSeconds: Double
    let pointsPerSecond: CGFloat
    let labelWidth: CGFloat
    let rowHeight: CGFloat
    let onSelect: () -> Void
    let onToggleVisibility: () -> Void

    var body: some View {
        let start = CGFloat(max(0, layer.inPoint.seconds)) * pointsPerSecond
        let end = CGFloat(min(compositionSeconds, layer.outPoint.seconds)) * pointsPerSecond
        let barWidth = max(4, end - start)

        HStack(spacing: 0) {
            HStack(spacing: 2) {
                Button(action: onToggleVisibility) {
                    Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(layer.isVisible ? Theme.textPrimary : Theme.textSecondary)
                        .frame(width: 40, height: rowHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(layer.isVisible ? "Hide \(layer.name)" : "Show \(layer.name)")

                Text(layer.name)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(layer.isVisible ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
            }
            .frame(width: labelWidth, alignment: .leading)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(layer.fill.color.opacity(layer.isVisible ? 0.82 : 0.28))
                    .frame(width: barWidth, height: rowHeight - 16)
                    .offset(x: start)
                ForEach(layer.keyframeTimes, id: \.self) { time in
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.keyframe)
                        .shadow(color: .black.opacity(0.55), radius: 1)
                        .offset(x: CGFloat(time.seconds) * pointsPerSecond - 5)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
        }
        .frame(height: rowHeight)
        .background(isSelected ? Theme.accent.opacity(0.16) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .accessibilityElement(children: .contain)
    }
}
