import SwiftUI
import MotionCore

/// The properties of the selected layer. Every row has a keyframe diamond: tap it to add a
/// keyframe at the current frame. Once a property has keyframes, editing it creates keyframes.
@MainActor
struct InspectorView: View {
    let model: EditorModel
    @State private var scaleLinked = true

    var body: some View {
        if let layer = model.selectedLayer {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 20) {
                    RenameField(layerName: layer.name) { model.rename(layer.id, to: $0) }
                        .id(layer.id)

                    swatches(for: layer)

                    VStack(spacing: 6) {
                        positionRow(layer)
                        scaleRow(layer)
                        sliderRow(layer, key: .rotation, range: -360...360, unit: 1, suffix: "°")
                        sliderRow(layer, key: .opacity, range: 0...1, unit: 100, suffix: "%")
                    }

                    keyframeSection(layer)

                    HStack(spacing: 10) {
                        actionButton("Duplicate", systemName: "plus.square.on.square") { model.duplicateSelected() }
                        actionButton("Delete", systemName: "trash", isDestructive: true) { model.deleteSelected() }
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "hand.tap")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Theme.textSecondary)
                Text("Select a layer")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text("Tap a layer in the preview or the timeline to edit it.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Rows

    private func keyframeState(_ layer: Layer, _ key: PropertyKey) -> KeyframeState {
        if layer.hasKeyframe(key, at: model.currentTime) { return .onKeyframe }
        return layer.isAnimated(key) ? .animated : .fixed
    }

    private func positionRow(_ layer: Layer) -> some View {
        let value = layer.vectorValue(.position, at: model.currentTime) ?? .zero
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(PropertyKey.position.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                KeyframeButton(state: keyframeState(layer, .position), propertyName: "position") {
                    model.toggleKeyframe(.position, layerID: layer.id)
                }
            }
            HStack(spacing: 10) {
                NumberField(title: "X", value: value.x) { newX in
                    model.setVector(.position, of: layer.id, to: Vec2(x: newX, y: value.y), coalescing: false)
                }
                NumberField(title: "Y", value: value.y) { newY in
                    model.setVector(.position, of: layer.id, to: Vec2(x: value.x, y: newY), coalescing: false)
                }
            }
        }
    }

    /// A slider row for scale, rotation and opacity. `unit` converts the stored number to what is shown
    /// (opacity 0...1 is shown as 0...100 percent).
    private func sliderRow(_ layer: Layer, key: PropertyKey, range: ClosedRange<Double>,
                           unit: Double, suffix: String) -> some View {
        let current: Double
        if key.isVector {
            current = layer.vectorValue(key, at: model.currentTime)?.x ?? 1
        } else {
            current = layer.scalarValue(key, at: model.currentTime) ?? 0
        }
        let binding = Binding<Double>(
            get: { current },
            set: { newValue in
                if key.isVector {
                    // Only used for properties that hold a single number in the slider (none at present).
                    model.setVector(key, of: layer.id, to: Vec2(x: newValue, y: newValue), coalescing: true)
                } else {
                    model.setScalar(key, of: layer.id, to: newValue, coalescing: true)
                }
            })
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(key.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(String(format: "%.0f", current * unit) + suffix)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
                KeyframeButton(state: keyframeState(layer, key), propertyName: key.displayName.lowercased()) {
                    model.toggleKeyframe(key, layerID: layer.id)
                }
            }
            Slider(value: binding, in: range, onEditingChanged: { editing in
                if !editing { model.endEditGroup() }
            })
            .accessibilityLabel(key.displayName)
        }
    }

    /// Width and height scale as separate numbers, with a link button to keep them equal.
    private func scaleRow(_ layer: Layer) -> some View {
        let value = layer.vectorValue(.scale, at: model.currentTime) ?? .one
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(PropertyKey.scale.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button { scaleLinked.toggle() } label: {
                    Image(systemName: "link")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(scaleLinked ? Theme.accent : Theme.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(scaleLinked ? "Width and height linked" : "Width and height separate")
                KeyframeButton(state: keyframeState(layer, .scale), propertyName: "scale") {
                    model.toggleKeyframe(.scale, layerID: layer.id)
                }
            }
            HStack(spacing: 10) {
                NumberField(title: "X %", value: value.x * 100) { percent in
                    let x = percent / 100
                    model.setVector(.scale, of: layer.id, to: Vec2(x: x, y: scaleLinked ? x : value.y), coalescing: false)
                }
                NumberField(title: "Y %", value: value.y * 100) { percent in
                    let y = percent / 100
                    model.setVector(.scale, of: layer.id, to: Vec2(x: scaleLinked ? y : value.x, y: y), coalescing: false)
                }
            }
        }
    }

    /// Easing, copy, paste and delete for the keyframe selected in the timeline.
    private func keyframeSection(_ layer: Layer) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Keyframes")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                IconButton(systemName: "chevron.left", label: "Previous keyframe") { model.jumpToKeyframe(forward: false) }
                IconButton(systemName: "chevron.right", label: "Next keyframe") { model.jumpToKeyframe(forward: true) }
            }

            if let reference = model.selectedKeyframe, reference.layerID == layer.id,
               let snapshot = model.selectedKeyframeSnapshot {
                let frame = model.composition.frameRate.frameIndex(at: reference.time)
                let isLast = layer.keyframeSnapshots(reference.property).last?.time == reference.time
                Text("\(reference.property.displayName) keyframe at frame \(frame)")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(EasingPreset.allCases) { preset in
                            let isCurrent = EasingPreset.matching(snapshot.outgoing) == preset
                            Button { model.setSelectedKeyframeEasing(preset) } label: {
                                Text(preset.displayName)
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(isCurrent ? Color.white : Theme.textPrimary)
                                    .padding(.horizontal, 12)
                                    .frame(height: 36)
                                    .background(isCurrent ? Theme.accent : Theme.surfaceRaised, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                EasingCurveView(interpolation: snapshot.outgoing)

                Text(isLast
                     ? "This is the last keyframe, so its easing has no effect until another keyframe follows."
                     : "Easing shapes the movement from this keyframe to the next one.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)

                HStack(spacing: 10) {
                    actionButton("Copy", systemName: "doc.on.doc") { model.copySelectedKeyframe() }
                    actionButton("Paste", systemName: "doc.on.clipboard") { model.pasteKeyframe() }
                        .opacity(model.copiedKeyframe == nil ? 0.4 : 1)
                        .disabled(model.copiedKeyframe == nil)
                    actionButton("Delete", systemName: "trash", isDestructive: true) { model.deleteSelectedKeyframe() }
                }
            } else {
                Text("Tap a diamond in the timeline to select a keyframe, then change its easing here. Use the diamonds beside each property to add keyframes.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                if model.copiedKeyframe != nil {
                    actionButton("Paste at playhead", systemName: "doc.on.clipboard") { model.pasteKeyframe() }
                }
            }
        }
    }

    private func swatches(for layer: Layer) -> some View {
        HStack(spacing: 12) {
            ForEach(0..<LayerPalette.colors.count, id: \.self) { index in
                let color = LayerPalette.colors[index]
                Button {
                    model.setFill(layer.id, to: color)
                } label: {
                    Circle()
                        .fill(color.color)
                        .frame(width: 30, height: 30)
                        .overlay(Circle().strokeBorder(Color.white.opacity(layer.fill == color ? 0.95 : 0.12),
                                                       lineWidth: layer.fill == color ? 2.5 : 1))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Colour \(index + 1)")
            }
        }
    }

    private func actionButton(_ title: String, systemName: String, isDestructive: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isDestructive ? Theme.danger : Theme.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// A text field that renames the layer when you press Return (one undo step, not one per letter).
private struct RenameField: View {
    let layerName: String
    let onCommit: (String) -> Void
    @State private var draft: String

    init(layerName: String, onCommit: @escaping (String) -> Void) {
        self.layerName = layerName
        self.onCommit = onCommit
        _draft = State(initialValue: layerName)
    }

    var body: some View {
        TextField("Layer name", text: $draft)
            .font(.title3.weight(.semibold))
            .submitLabel(.done)
            .onSubmit { onCommit(draft) }
            .onChange(of: layerName) { _, newName in draft = newName }
            .foregroundStyle(Theme.textPrimary)
    }
}
