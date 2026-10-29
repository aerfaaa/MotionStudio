import SwiftUI
import MotionCore

/// The properties of the selected layer. Every row has a keyframe diamond: tap it to add a
/// keyframe at the current frame. Once a property has keyframes, editing it creates keyframes.
@MainActor
struct InspectorView: View {
    let model: EditorModel
    @State private var scaleLinked = true
    @State private var showCustomGraph = false
    @State private var padStartPosition: Vec2?
    @AppStorage("motionStudioTransformPadSensitivity") private var transformPadSensitivity: Double = 0.25

    var body: some View {
        if let layer = model.selectedLayer {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 20) {
                    RenameField(layerName: layer.name) { model.rename(layer.id, to: $0) }
                        .id(layer.id)
                                        if case .audio = layer.kind {
                        EmptyView()
                    } else if case .null = layer.kind {
                        EmptyView()
                    } else {
                        universalRecolourControl(layer)
                    }
                    switch layer.kind {
                    case .image(let assetID):
                        imageInfo(layer: layer, assetID: assetID)
                    case .video(let assetID):
                        videoInfo(layer: layer, assetID: assetID)
                    case .audio(let assetID):
                        audioInfo(assetID: assetID)
                    case .text(let content):
                        textEditor(layer: layer, content: content)
                    case .adjustment:
                        EmptyView()
                    default:
                        swatches(for: layer)
                    }

                    if case .adjustment = layer.kind {
                        Label("Effects from this layer are applied to visual layers beneath it in the timeline. Drag it above or below clips to change which clips receive the effects.", systemImage: "slider.horizontal.3")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Transform")
                                .font(.headline)
                                .foregroundStyle(Theme.textPrimary)
                            dragPad(layer)
                            positionRow(layer)
                            sizeRow(layer)
                            scaleRow(layer)
                            sliderRow(layer, key: .rotation, range: -360...360, unit: 1, suffix: "°")
                            sliderRow(layer, key: .opacity, range: 0...1, unit: 100, suffix: "%")
                            playbackSpeedRow(layer)
                        }

                        keyframeSection(layer)
                        parentSection(layer)
                    }

                    if case .video = layer.kind {
                        actionButton("Extract Audio", systemName: "waveform") {
                            model.extractAudio(fromVideoLayerID: layer.id)
                        }
                    }

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

    private func dragPad(_ layer: Layer) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Drag here to move layer")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("\(Int(transformPadSensitivity * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
            }
            Slider(value: $transformPadSensitivity, in: 0.05...1.0, step: 0.05)
                .accessibilityLabel("Transform pad sensitivity")
            GeometryReader { geometry in
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Theme.surfaceRaised)
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Theme.hairline, lineWidth: 1)
                    Path { path in
                        path.move(to: CGPoint(x: geometry.size.width / 2, y: 8))
                        path.addLine(to: CGPoint(x: geometry.size.width / 2, y: geometry.size.height - 8))
                        path.move(to: CGPoint(x: 8, y: geometry.size.height / 2))
                        path.addLine(to: CGPoint(x: geometry.size.width - 8, y: geometry.size.height / 2))
                    }
                    .stroke(Theme.textSecondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    Image(systemName: "move.3d")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                .contentShape(RoundedRectangle(cornerRadius: 12))
                .gesture(DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if padStartPosition == nil {
                            padStartPosition = layer.vectorValue(.position, at: model.currentTime) ?? .zero
                        }
                        guard let start = padStartPosition else { return }
                        let width = max(geometry.size.width, 1)
                        let height = max(geometry.size.height, 1)
                        // Sensitivity is independent of composition size. Low values allow fine nudges.
                        let dx = Double(value.translation.width / width) * Double(model.composition.width) * transformPadSensitivity
                        let dy = Double(value.translation.height / height) * Double(model.composition.height) * transformPadSensitivity
                        model.movePosition(of: layer.id, to: Vec2(x: start.x + dx, y: start.y + dy))
                    }
                    .onEnded { _ in
                        padStartPosition = nil
                        model.endEditGroup()
                    })
                .accessibilityLabel("Layer movement pad")
                .accessibilityHint("Drag in any direction to move the selected layer without covering the preview.")
            }
            .frame(height: 84)
        }
    }

    private func textEditor(layer: Layer, content: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Text")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
            TextField("Enter text", text: Binding(
                get: { if case .text(let value)? = model.selectedLayer?.kind { return value }; return content },
                set: { model.setText(layer.id, to: $0) }
            ), axis: .vertical)
            .lineLimit(2...5)
            .textFieldStyle(.roundedBorder)
            Picker("Font", selection: Binding<String?>(
                get: { model.selectedLayer?.textFontName },
                set: { model.setTextFont(layer.id, to: $0) }
            )) {
                Text("System").tag(Optional<String>.none)
                ForEach(model.customFontNames, id: \.self) { name in
                    Text(name).tag(Optional(name))
                }
            }
            .pickerStyle(.menu)
            if model.customFontNames.isEmpty {
                Text("Import a .ttf or .otf font through the media importer to make it available here.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            ColorPicker("Text colour", selection: Binding<Color>(
                get: { layer.fill.color },
                set: { model.setFill(layer.id, to: RGBA(color: $0)) }
            ), supportsOpacity: true)
        }
    }

    private func playbackSpeedRow(_ layer: Layer) -> some View {
        let opticalFlowEnabled = layer.effects.contains(where: { $0.effectID == "optical-flow-slow-motion" && $0.isEnabled })
        let isVideoLayer: Bool = { if case .video = layer.kind { return true }; return false }()
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(isVideoLayer && opticalFlowEnabled ? "Video playback speed" : "Animation speed", systemImage: "speedometer")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(String(format: "%.2g×", layer.playbackSpeed))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
            }
            Slider(value: Binding(get: { layer.playbackSpeed }, set: { model.setPlaybackSpeed(layer.id, to: $0) }),
                   in: 0.25...4, step: 0.25)
            HStack { Text("Slower"); Spacer(); Text("Faster") }
                .font(.caption2).foregroundStyle(Theme.textSecondary)
            Text(isVideoLayer && opticalFlowEnabled
                 ? "Slows the video source and synthesizes in-between frames during export. Lower values take longer to render and may create motion artifacts."
                 : "Changes the speed of keyframed motion and effect parameters. The clip's in/out points stay in place.")
                .font(.caption).foregroundStyle(Theme.textSecondary)
        }
    }

    private func universalRecolourControl(_ layer: Layer) -> some View {
        ColorPicker("Recolour layer", selection: Binding<Color>(
            get: {
                let effect = model.selectedLayer?.effects.first(where: { $0.effectID == "colorize" })
                func value(_ key: String, _ fallback: Double) -> Double {
                    guard let parameter = effect?.parameters[key] else { return fallback }
                    if case .scalar(let track) = parameter { return track.value(at: model.currentTime) }
                    return fallback
                }
                return Color(red: value("tintRed", 1), green: value("tintGreen", 0.35), blue: value("tintBlue", 0.1))
            },
            set: { color in
                let rgb = RGBA(color: color)
                var effect = model.selectedLayer?.effects.first(where: { $0.effectID == "colorize" })
                if effect == nil {
                    model.addEffect("colorize")
                    effect = model.selectedLayer?.effects.first(where: { $0.effectID == "colorize" })
                }
                guard let effect else { return }
                model.setEffectValues(effect.id, [
                    "tintRed": [rgb.r], "tintGreen": [rgb.g],
                    "tintBlue": [rgb.b], "amount": [1]
                ], coalescing: false)
            }
        ), supportsOpacity: false)
        .font(.subheadline)
    }

    private func parentSection(_ layer: Layer) -> some View {
        let nullLayers = model.composition.layers.filter { $0.kind == .null && $0.id != layer.id }
        return VStack(alignment: .leading, spacing: 6) {
            Text("Parent / Null")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
            Picker("Parent", selection: Binding<UUID?>(
                get: { model.selectedLayer?.parentID },
                set: { model.setParent(layer.id, to: $0) }
            )) {
                Text("None").tag(Optional<UUID>.none)
                ForEach(nullLayers) { parent in
                    Text(parent.name).tag(Optional(parent.id))
                }
            }
            .pickerStyle(.menu)
            .disabled(layer.kind == .null)
            Text("Parenting uses the existing null transform system. Child transforms follow the selected null.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func audioInfo(assetID: UUID) -> some View {
        let asset = model.project.assets.first(where: { $0.id == assetID })
        let missing = asset.map { !ProjectMedia.fileExists(for: $0, inProjectFolder: model.folderURL) } ?? true
        return VStack(alignment: .leading, spacing: 6) {
            Label(asset?.displayName ?? "Unknown audio", systemImage: "waveform")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            if missing {
                Label("The audio file is missing from project storage.", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(Theme.danger)
            }
            Text("Audio clip is on the timeline. Synchronized audio playback is not implemented yet.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func videoInfo(layer: Layer, assetID: UUID) -> some View {
        let asset = model.project.assets.first(where: { $0.id == assetID })
        let missing = asset.map { !ProjectMedia.fileExists(for: $0, inProjectFolder: model.folderURL) } ?? true
        return VStack(alignment: .leading, spacing: 6) {
            Label(asset?.displayName ?? "Unknown video", systemImage: "video")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            if let asset, let url = ProjectMedia.fileURL(for: asset, inProjectFolder: model.folderURL) {
                Text(url.pathExtension.uppercased() + " video · poster-frame preview")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            if missing {
                Label("The video file is missing from project storage.", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(Theme.danger)
            }
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

    /// Direct pixel-size controls, similar to the quick transform panel in mobile motion editors.
    /// The underlying layer dimensions stay unchanged; these controls update its scale.
    private func sizeRow(_ layer: Layer) -> some View {
        let scale = layer.vectorValue(.scale, at: model.currentTime) ?? .one
        let width = max(1, layer.size.x * scale.x)
        let height = max(1, layer.size.y * scale.y)
        return VStack(alignment: .leading, spacing: 4) {
            Text("Size (px)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
            HStack(spacing: 10) {
                NumberField(title: "W", value: width) { newWidth in
                    let newScaleX = max(0.01, newWidth) / max(layer.size.x, 1)
                    let newScaleY = scaleLinked ? newScaleX : scale.y
                    model.setVector(.scale, of: layer.id, to: Vec2(x: newScaleX, y: newScaleY), coalescing: false)
                }
                NumberField(title: "H", value: height) { newHeight in
                    let newScaleY = max(0.01, newHeight) / max(layer.size.y, 1)
                    let newScaleX = scaleLinked ? newScaleY : scale.x
                    model.setVector(.scale, of: layer.id, to: Vec2(x: newScaleX, y: newScaleY), coalescing: false)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Layer size in pixels")
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
                Text("Keyframes & interpolation")
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

                DisclosureGroup("Custom graph", isExpanded: $showCustomGraph) {
                    let ease: BezierEase = {
                        if case .bezier(let current) = snapshot.outgoing { return current }
                        return .easeInOut
                    }()
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Adjust the two Bezier handles. X controls timing; Y controls progress and can overshoot.")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                        customGraphSlider("Handle 1 · X", value: ease.x1, range: 0...1) { value in
                            model.setSelectedKeyframeCustomEasing(BezierEase(value, ease.y1, ease.x2, ease.y2))
                        }
                        customGraphSlider("Handle 1 · Y", value: ease.y1, range: -0.5...1.5) { value in
                            model.setSelectedKeyframeCustomEasing(BezierEase(ease.x1, value, ease.x2, ease.y2))
                        }
                        customGraphSlider("Handle 2 · X", value: ease.x2, range: 0...1) { value in
                            model.setSelectedKeyframeCustomEasing(BezierEase(ease.x1, ease.y1, value, ease.y2))
                        }
                        customGraphSlider("Handle 2 · Y", value: ease.y2, range: -0.5...1.5) { value in
                            model.setSelectedKeyframeCustomEasing(BezierEase(ease.x1, ease.y1, ease.x2, value))
                        }
                        Button("Reset to smooth ease") { model.setSelectedKeyframeCustomEasing(.easeInOut) }
                            .buttonStyle(.bordered)
                    }
                    .padding(.top, 8)
                }
                .font(.subheadline.weight(.medium))

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

    private func customGraphSlider(_ title: String, value: Double, range: ClosedRange<Double>,
                                   onChange: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.caption)
                Spacer()
                Text(value.formatted(.number.precision(.fractionLength(2))))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
            }
            Slider(value: Binding(get: { value }, set: onChange), in: range)
                .tint(Theme.accent)
        }
    }

    /// Shows which picture the layer uses, and says so clearly if its file is missing.
    private func imageInfo(layer: Layer, assetID: UUID) -> some View {
        let asset = model.project.assets.first(where: { $0.id == assetID })
        let isMissing = asset.map { !ProjectMedia.fileExists(for: $0, inProjectFolder: model.folderURL) } ?? true
        return VStack(alignment: .leading, spacing: 4) {
            Label(asset?.displayName ?? "Unknown picture", systemImage: "photo")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            if let size = asset?.pixelSize {
                Text("\(Int(size.x)) by \(Int(size.y)) pixels")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            if isMissing {
                Label("The picture file is missing from the project folder. The layer shows a grey placeholder.",
                      systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(Theme.danger)
            }
        }
    }

    private func swatches(for layer: Layer) -> some View {
        VStack(alignment: .leading, spacing: 8) {
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
            ColorPicker("Custom colour", selection: Binding<Color>(
                get: { layer.fill.color },
                set: { model.setFill(layer.id, to: RGBA(color: $0)) }
            ), supportsOpacity: true)
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
