import SwiftUI
import UIKit
import MotionCore

/// A scrollable, zoomable timeline with frame-aligned trim handles and keyframe tracks.
@MainActor
struct TimelinePanel: View {
    let model: EditorModel

    private let rowHeight: CGFloat = 46
    private let rulerHeight: CGFloat = 38
    @AppStorage("motionStudioTimelineZoom") private var zoom: Double = 1.0
    @AppStorage("motionStudioClipEdgeSnapping") private var clipEdgeSnapping = true

    static let shownProperties: [PropertyKey] = [.position, .scale, .rotation, .opacity]

    var body: some View {
        GeometryReader { geometry in
            let _ = model.previewCacheVersion
            let width = geometry.size.width
            let labelWidth: CGFloat = width < 420 ? 112 : 176
            let viewportTrackWidth = max(1, width - labelWidth)
            let duration = max(model.composition.duration.seconds, 0.001)
            let basePointsPerSecond = viewportTrackWidth / CGFloat(duration)
            let pointsPerSecond = basePointsPerSecond * CGFloat(min(max(zoom, 1), 12))
            let contentWidth = max(width, labelWidth + CGFloat(duration) * pointsPerSecond)
            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    Label("\(model.composition.layers.count) layers", systemImage: "square.3.layers.3d")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Label("Cached", systemImage: "circle.fill")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Theme.success)
                    Button {
                        clipEdgeSnapping.toggle()
                        MotionStudioHaptics.selection()
                    } label: {
                        Label(clipEdgeSnapping ? "Snap on" : "Snap off", systemImage: "dot.scope")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(clipEdgeSnapping ? Theme.accent : Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(clipEdgeSnapping ? "Disable clip edge snapping" : "Enable clip edge snapping")
                    Spacer(minLength: 4)
                    Button { zoom = max(1, zoom / 1.25) } label: {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Zoom timeline out")
                    Slider(value: $zoom, in: 1...12, step: 0.25)
                        .frame(maxWidth: 110)
                        .accessibilityLabel("Timeline zoom")
                    Button { zoom = min(12, zoom * 1.25) } label: {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Zoom timeline in")
                }
                .font(.caption)
                .padding(.horizontal, 8)

                ScrollView(.horizontal) {
                    ZStack(alignment: .topLeading) {
                        VStack(spacing: 0) {
                            HStack(spacing: 0) {
                                Text("Layer / property")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textSecondary)
                                    .padding(.leading, 10)
                                    .frame(width: labelWidth, height: rulerHeight, alignment: .leading)
                                TimelineRuler(duration: duration, pointsPerSecond: pointsPerSecond,
                                              frameRate: model.composition.frameRate,
                                              renderedFrames: model.cachedPreviewFrameIndices) { x in
                                    model.seek(toSeconds: Double(x / pointsPerSecond))
                                }
                                .frame(width: contentWidth - labelWidth, height: rulerHeight)
                            }
                            Rectangle().fill(Theme.hairline).frame(height: 1)

                            if model.composition.layers.isEmpty {
                                Text("No layers yet. Tap + to add a shape or import media.")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.textSecondary)
                                    .frame(width: contentWidth)
                                    .frame(minHeight: 100)
                            } else {
                                ScrollView(.vertical) {
                                    VStack(spacing: 0) {
                                        ForEach(model.composition.layers.indices, id: \.self) { index in
                                            let layer = model.composition.layers[index]
                                            LayerRow(layer: layer,
                                                     allLayers: model.composition.layers,
                                                     layerIndex: index,
                                                     layerCount: model.composition.layers.count,
                                                     audioURL: audioURL(for: layer),
                                                     isSelected: layer.id == model.selectedLayerID,
                                                     compositionSeconds: duration,
                                                     frameRate: model.composition.frameRate,
                                                     pointsPerSecond: pointsPerSecond,
                                                     labelWidth: labelWidth,
                                                     rowHeight: rowHeight,
                                                     clipEdgeSnapping: clipEdgeSnapping,
                                                     onSelect: { model.select(layer.id) },
                                                     onToggleVisibility: { model.setVisibility(layer.id, to: !layer.isVisible) },
                                                     onTrim: { input, output in
                                                         model.setLayerTiming(layer.id, inPoint: input, outPoint: output, coalescing: true)
                                                     },
                                                     onMove: { input, output in
                                                         model.setLayerTiming(layer.id, inPoint: input, outPoint: output, coalescing: true)
                                                     },
                                                     onTrimEnded: { model.endEditGroup() },
                                                     onMoveLayer: { draggedID, targetIndex in model.reorderLayer(draggedID, to: targetIndex) },
                                                     onDropLayer: { rawID in
                                                         guard let draggedID = UUID(uuidString: rawID) else { return false }
                                                         model.reorderLayer(draggedID, to: index)
                                                         return true
                                                     })
                                            if layer.id == model.selectedLayerID {
                                                ForEach(TimelinePanel.shownProperties, id: \.self) { key in
                                                    PropertyTrackRow(model: model, layer: layer, key: key,
                                                                     pointsPerSecond: pointsPerSecond, labelWidth: labelWidth)
                                                }
                                            }
                                        }
                                    }
                                }
                                .frame(width: contentWidth)
                                .frame(maxHeight: .infinity)
                            }
                        }
                        Capsule()
                            .fill(Theme.accent)
                            .frame(width: 2, height: max(1, geometry.size.height - 42))
                            .offset(x: labelWidth + CGFloat(model.currentTime.seconds) * pointsPerSecond - 1)
                            .allowsHitTesting(false)
                    }
                    .frame(width: contentWidth)
                    .frame(minHeight: geometry.size.height - 32, alignment: .topLeading)
                }
                .scrollIndicators(.visible)
            }
        }
    }

    private func audioURL(for layer: Layer) -> URL? {
        guard case .audio(let assetID) = layer.kind,
              let asset = model.project.assets.first(where: { $0.id == assetID }) else { return nil }
        return ProjectMedia.fileURL(for: asset, inProjectFolder: model.folderURL)
    }
}

private struct TimelineRuler: View {
    let duration: Double
    let pointsPerSecond: CGFloat
    let frameRate: FrameRate
    let renderedFrames: Set<Int64>
    let onScrub: (CGFloat) -> Void

    var body: some View {
        Canvas { context, size in
            // Coloured segments show frames whose fully composited preview is resident in RAM.
            var cacheBar = Path()
            for frame in renderedFrames where frame >= 0 {
                let start = CGFloat(frameRate.time(ofFrame: frame).seconds) * pointsPerSecond
                let frameWidth = max(1.5, pointsPerSecond / CGFloat(frameRate.framesPerSecond))
                let end = min(size.width, start + frameWidth)
                if start < size.width && end > start {
                    cacheBar.move(to: CGPoint(x: start, y: 1.5))
                    cacheBar.addLine(to: CGPoint(x: end, y: 1.5))
                }
            }
            context.stroke(cacheBar, with: .color(Theme.success), style: StrokeStyle(lineWidth: 3, lineCap: .round))
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
    @State private var trimStartOrigin: Time?
    @State private var trimEndOrigin: Time?
    @State private var clipDragStart: Time?
    @State private var clipDragEnd: Time?
    @State private var lastTrimHapticFrame: Int64?
    @State private var lastClipSnapKey: String?
    let layer: Layer
    let allLayers: [Layer]
    let layerIndex: Int
    let layerCount: Int
    let audioURL: URL?
    let isSelected: Bool
    let compositionSeconds: Double
    let frameRate: FrameRate
    let pointsPerSecond: CGFloat
    let labelWidth: CGFloat
    let rowHeight: CGFloat
    let clipEdgeSnapping: Bool
    let onSelect: () -> Void
    let onToggleVisibility: () -> Void
    let onTrim: (Time, Time) -> Void
    let onMove: (Time, Time) -> Void
    let onTrimEnded: () -> Void
    let onMoveLayer: (UUID, Int) -> Void
    let onDropLayer: (String) -> Bool

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

                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 16, height: rowHeight)
                    .contentShape(Rectangle())
                    .draggable(layer.id.uuidString)
                    .accessibilityLabel("Drag to rearrange \(layer.name)")

                if case .adjustment = layer.kind {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                Text(layer.name)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(layer.isVisible ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
            }
            .frame(width: labelWidth, alignment: .leading)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill((layer.timelineColor ?? layer.fill).color.opacity(layer.isVisible ? 0.72 : 0.22))
                    .frame(width: barWidth, height: rowHeight - 16)
                    .offset(x: start)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 3)
                        .onChanged { value in
                            let originStart = clipDragStart ?? layer.inPoint
                            let originEnd = clipDragEnd ?? layer.outPoint
                            clipDragStart = originStart
                            clipDragEnd = originEnd
                            let duration = max(Time(seconds: 1.0 / frameRate.framesPerSecond), originEnd - originStart)
                            let maxStart = max(0, compositionSeconds - duration.seconds)
                            let rawStart = min(maxStart, max(0, originStart.seconds + Double(value.translation.width / max(pointsPerSecond, 0.001))))
                            let otherClips = allLayers.filter { $0.id != layer.id }.map {
                                ClipInterval(id: $0.id, inPoint: $0.inPoint, outPoint: $0.outPoint)
                            }
                            let snapped = ClipSnapper.snapStart(
                                proposedStart: Time(seconds: rawStart),
                                clipDuration: duration,
                                compositionDuration: Time(seconds: compositionSeconds),
                                frameRate: frameRate,
                                otherClips: otherClips,
                                pointsPerSecond: Double(pointsPerSecond),
                                enabled: clipEdgeSnapping
                            )
                            let finalStart = snapped.start
                            let finalEnd = min(Time(seconds: compositionSeconds), finalStart + duration)
                            if snapped.snapKey != lastClipSnapKey {
                                if snapped.snapKey != nil { MotionStudioHaptics.impact(.medium) }
                                lastClipSnapKey = snapped.snapKey
                            }
                            onMove(finalStart, max(finalEnd, finalStart + Time(seconds: 1.0 / frameRate.framesPerSecond)))
                        }
                        .onEnded { _ in
                            clipDragStart = nil
                            clipDragEnd = nil
                            lastClipSnapKey = nil
                            onTrimEnded()
                        })

                if let audioURL {
                    AudioWaveformView(url: audioURL, tint: Theme.accent, barCount: max(36, Int(barWidth / 2.5)))
                        .frame(width: max(1, barWidth - 8), height: rowHeight - 20)
                        .offset(x: start + 4)
                        .allowsHitTesting(false)
                }

                // Drag the left edge to change the in-point. Changes snap to composition frames.
                Capsule()
                    .fill(Theme.textPrimary.opacity(0.95))
                    .frame(width: 8, height: rowHeight - 12)
                    .offset(x: start - 4)
                    .gesture(DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            let origin = trimStartOrigin ?? layer.inPoint
                            trimStartOrigin = origin
                            let proposed = max(0, min(layer.outPoint.seconds - (1.0 / frameRate.framesPerSecond),
                                origin.seconds + Double(value.translation.width / max(pointsPerSecond, 0.001))))
                            let snapped = frameRate.snapped(Time(seconds: proposed))
                            let frame = frameRate.frameIndex(at: snapped)
                            if lastTrimHapticFrame != frame {
                                MotionStudioHaptics.impact(.light)
                                lastTrimHapticFrame = frame
                            }
                            onTrim(snapped, layer.outPoint)
                        }
                        .onEnded { _ in
                            trimStartOrigin = nil
                            lastTrimHapticFrame = nil
                            onTrimEnded()
                        })
                    .accessibilityLabel("Trim \(layer.name) start")

                // Drag the right edge to change the out-point.
                Capsule()
                    .fill(Theme.textPrimary.opacity(0.95))
                    .frame(width: 8, height: rowHeight - 12)
                    .offset(x: start + barWidth - 4)
                    .gesture(DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            let origin = trimEndOrigin ?? layer.outPoint
                            trimEndOrigin = origin
                            let proposed = max(layer.inPoint.seconds + (1.0 / frameRate.framesPerSecond), min(compositionSeconds,
                                origin.seconds + Double(value.translation.width / max(pointsPerSecond, 0.001))))
                            let snapped = frameRate.snapped(Time(seconds: proposed))
                            let frame = frameRate.frameIndex(at: snapped)
                            if lastTrimHapticFrame != frame {
                                MotionStudioHaptics.impact(.light)
                                lastTrimHapticFrame = frame
                            }
                            onTrim(layer.inPoint, snapped)
                        }
                        .onEnded { _ in
                            trimEndOrigin = nil
                            lastTrimHapticFrame = nil
                            onTrimEnded()
                        })
                    .accessibilityLabel("Trim \(layer.name) end")

                ForEach(layer.keyframeTimes, id: \.self) { time in
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.keyframe)
                        .shadow(color: .black.opacity(0.55), radius: 1)
                        .offset(x: CGFloat(time.seconds) * pointsPerSecond - 5)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
        }
        .frame(height: rowHeight)
        .background(isSelected ? Theme.accent.opacity(0.16) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .dropDestination(for: String.self) { items, _ in
            guard let rawID = items.first else { return false }
            return onDropLayer(rawID)
        }
        .contextMenu {
            Button { onMoveLayer(layer.id, 0) } label: { Label("Move to Top", systemImage: "arrow.up.to.line") }
            Button { onMoveLayer(layer.id, max(0, layerIndex - 1)) } label: { Label("Move Up", systemImage: "arrow.up") }
                .disabled(layerIndex == 0)
            Button { onMoveLayer(layer.id, min(layerCount - 1, layerIndex + 1)) } label: { Label("Move Down", systemImage: "arrow.down") }
                .disabled(layerIndex >= layerCount - 1)
            Button { onMoveLayer(layer.id, max(0, layerCount - 1)) } label: { Label("Move to Bottom", systemImage: "arrow.down.to.line") }
        }
        .accessibilityElement(children: .contain)
    }


}

/// One property of the selected layer: a lane of keyframe diamonds.
/// Tap a diamond to select it. Drag it sideways to retime it (it snaps to whole frames).
/// Tap empty space in the lane to clear the selection.
private struct PropertyTrackRow: View {
    let model: EditorModel
    let layer: Layer
    let key: PropertyKey
    let pointsPerSecond: CGFloat
    let labelWidth: CGFloat

    @State private var started = false
    @State private var grabbed: Time?
    @State private var moving = false

    var body: some View {
        let snapshots = layer.keyframeSnapshots(key)
        HStack(spacing: 0) {
            Text(key.displayName)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .padding(.leading, 48)
                .frame(width: labelWidth, alignment: .leading)

            ZStack(alignment: .leading) {
                Rectangle().fill(Color.clear)
                ForEach(snapshots, id: \.time) { snapshot in
                    diamond(at: snapshot.time)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !started {
                            started = true
                            grabbed = nearestKeyframe(toX: value.startLocation.x, in: snapshots)
                            if let time = grabbed {
                                model.selectKeyframe(layerID: layer.id, property: key, time: time)
                            }
                        }
                        guard grabbed != nil else { return }
                        // A tap must not move anything: wait until the finger has really moved.
                        if !moving && abs(value.translation.width) < 6 { return }
                        moving = true
                        model.moveSelectedKeyframe(toFrame: frame(forX: value.location.x))
                    }
                    .onEnded { _ in
                        if grabbed == nil {
                            model.clearKeyframeSelection()
                        } else if moving {
                            model.endEditGroup()
                        }
                        started = false
                        grabbed = nil
                        moving = false
                    }
            )
        }
        .frame(height: 36)
        .background(Theme.surfaceRaised.opacity(0.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(key.displayName) keyframes, \(snapshots.count)")
    }

    private func diamond(at time: Time) -> some View {
        let isSelected = model.selectedKeyframe == KeyframeRef(layerID: layer.id, property: key, time: time)
        return Image(systemName: "diamond.fill")
            .font(.system(size: isSelected ? 16 : 12))
            .foregroundStyle(Theme.keyframe)
            .overlay {
                if isSelected {
                    Image(systemName: "diamond")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            .frame(width: 30, height: 36)
            .offset(x: CGFloat(time.seconds) * pointsPerSecond - 15)
            .allowsHitTesting(false)
    }

    private func xPosition(of time: Time) -> CGFloat {
        CGFloat(time.seconds) * pointsPerSecond
    }

    private func nearestKeyframe(toX x: CGFloat, in snapshots: [KeyframeSnapshot]) -> Time? {
        let best = snapshots.min(by: { abs(xPosition(of: $0.time) - x) < abs(xPosition(of: $1.time) - x) })
        guard let best, abs(xPosition(of: best.time) - x) <= 24 else { return nil }
        return best.time
    }

    private func frame(forX x: CGFloat) -> Int64 {
        let seconds = Double(max(0, x) / max(pointsPerSecond, 0.001))
        return model.composition.frameRate.frameIndex(at: Time(seconds: seconds))
    }
}
