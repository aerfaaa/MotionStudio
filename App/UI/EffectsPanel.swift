import SwiftUI
import UIKit
import MotionCore

/// The Effects panel: the effects on the selected image layer, in the order they run, with their settings.
@MainActor
struct EffectsPanel: View {
    let model: EditorModel
    @State private var showingBrowser = false

    var body: some View {
        Group {
            if let layer = model.selectedLayer {
                if let message = EffectRegistry.applicabilityMessage(for: layer.kind) {
                    notice(icon: "photo", title: "Effects need an image layer", text: message)
                } else {
                    content(for: layer)
                }
            } else {
                notice(icon: "hand.tap", title: "Select a layer",
                       text: "Select an image layer, then add effects to it here.")
            }
        }
        .sheet(isPresented: $showingBrowser) {
            EffectBrowserSheet(model: model)
        }
    }

    // MARK: Layout

    private func notice(icon: String, title: String, text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.textSecondary)
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func content(for layer: Layer) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Effects on \(layer.name)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Button { showingBrowser = true } label: {
                        Label("Add effect", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 14)
                            .frame(height: 40)
                            .background(Theme.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("QUICK LOOKS")
                            .font(.caption.weight(.bold))
                            .tracking(1)
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text("Adds editable effects")
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            quickLookButton("Cinematic", symbol: "movieclapper") {
                                model.addEffect("color-temperature")
                                model.addEffect("vignette")
                                model.addEffect("film-grain")
                            }
                            quickLookButton("Film", symbol: "film") {
                                model.addEffect("film-grain")
                                model.addEffect("vignette")
                            }
                            quickLookButton("Glitch", symbol: "waveform.path") {
                                model.addEffect("chromatic-aberration")
                                model.addEffect("rgb-split")
                                model.addEffect("vhs")
                            }
                            quickLookButton("Retro screen", symbol: "tv") {
                                model.addEffect("scanlines")
                                model.addEffect("vhs")
                                model.addEffect("rgb-split")
                            }
                            quickLookButton("Soft glow", symbol: "sparkles") {
                                model.addEffect("glow")
                                model.addEffect("vignette")
                            }
                            quickLookButton("Pop colour", symbol: "paintpalette.fill") {
                                model.addEffect("saturation-vibrance")
                                model.addEffect("sharpen")
                            }
                            quickLookButton("Dreamy", symbol: "cloud.fill") {
                                model.addEffect("gaussian-blur")
                                model.addEffect("glow")
                                model.addEffect("vignette")
                            }
                            quickLookButton("Neon", symbol: "bolt.fill") {
                                model.addEffect("edge-glow")
                                model.addEffect("chromatic-aberration")
                                model.addEffect("saturation-vibrance")
                            }
                            quickLookButton("Night vision", symbol: "eye.fill") {
                                model.addEffect("colorize")
                                model.addEffect("noise")
                                model.addEffect("edge-glow")
                            }
                            quickLookButton("Bloom", symbol: "sun.max.fill") {
                                model.addEffect("bloom")
                                model.addEffect("vignette")
                            }
                            quickLookButton("Duotone", symbol: "circle.lefthalf.filled") {
                                model.addEffect("duotone")
                                model.addEffect("film-grain")
                            }
                            quickLookButton("Digital glitch", symbol: "waveform.path.ecg") {
                                model.addEffect("glitch-lines")
                                model.addEffect("rgb-split")
                                model.addEffect("chromatic-aberration")
                            }
                            quickLookButton("Mono", symbol: "circle.lefthalf.filled") {
                                model.addEffect("black-white")
                                model.addEffect("film-grain")
                                model.addEffect("vignette")
                            }
                            quickLookButton("Pixel art", symbol: "square.grid.3x3.fill") {
                                model.addEffect("pixelate")
                                model.addEffect("posterize")
                            }
                        }
                    }
                }
                .padding(12)
                .background(Theme.surface.opacity(0.65), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Theme.hairline, lineWidth: 1)
                }

                if case .adjustment = layer.kind {
                    Label("Adjustment layer: effects are passed to every visible visual layer below this row. Move the layer in the timeline to change its range.", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 10))
                }

                if layer.effects.isEmpty {
                    Text("No effects yet. Tap Add effect to choose one. Effects run from top to bottom, so their order changes the result.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(Array(layer.effects.enumerated()), id: \.element.id) { index, effect in
                            row(effect, index: index, count: layer.effects.count)
                        }
                    }
                }

                if let problems = model.images.issues[layer.id], !problems.isEmpty {
                    ForEach(Array(problems.enumerated()), id: \.offset) { _, issue in
                        Label(issue.message, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(Theme.danger)
                    }
                }

                if let effect = layer.effects.first(where: { $0.id == model.selectedEffectID }),
                   let definition = EffectRegistry.definition(id: effect.effectID),
                   EffectRegistry.isAvailable(id: effect.effectID) {
                    parameterSection(effect: effect, definition: definition)
                }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func quickLookButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            MotionStudioHaptics.selection()
            action()
        } label: {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 11)
                .frame(height: 36)
                .background(Theme.surfaceRaised, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Effect rows

    private func row(_ effect: EffectInstance, index: Int, count: Int) -> some View {
        let definition = EffectRegistry.definition(id: effect.effectID)
        let available = EffectRegistry.isAvailable(id: effect.effectID)
        let isSelected = effect.id == model.selectedEffectID
        return HStack(spacing: 8) {
            Toggle("Enabled", isOn: Binding(get: { effect.isEnabled },
                                             set: { model.setEffectEnabled(effect.id, $0) }))
                .labelsHidden()
                .disabled(!available)
                .accessibilityLabel("\(definition?.name ?? "Effect") enabled")
            Button { model.selectedEffectID = effect.id } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(definition?.name ?? "Unknown effect")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(available ? Theme.textPrimary : Theme.danger)
                        .lineLimit(1)
                    if !available {
                        Text(definition == nil ? "Not recognised, it is skipped" : "Not available yet, it is skipped")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    } else if !effect.isEnabled {
                        Text("Off")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Menu {
                Button { model.moveEffect(effect.id, by: -1) } label: { Label("Move up", systemImage: "arrow.up") }
                    .disabled(index == 0)
                Button { model.moveEffect(effect.id, by: 1) } label: { Label("Move down", systemImage: "arrow.down") }
                    .disabled(index == count - 1)
                if available {
                    Button { model.resetEffect(effect.id) } label: { Label("Reset settings", systemImage: "arrow.counterclockwise") }
                }
                Divider()
                Button(role: .destructive) { model.removeEffect(effect.id) } label: { Label("Remove", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Options for \(definition?.name ?? "effect")")
        }
        .padding(.leading, 12)
        .background(isSelected ? Theme.accent.opacity(0.16) : Theme.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
    }

    // MARK: Settings

    private enum SettingItem: Identifiable {
        case plain(EffectParameterDefinition)
        case colour(prefix: String, title: String)

        var id: String {
            switch self {
            case .plain(let rule): return rule.id
            case .colour(let prefix, _): return prefix + "-colour"
            }
        }
    }

    /// Three settings named <prefix>Red, <prefix>Green and <prefix>Blue are shown as one colour picker.
    private func items(for definition: EffectDefinition) -> [SettingItem] {
        let ids = Set(definition.parameters.map { $0.id })
        var result: [SettingItem] = []
        for rule in definition.parameters {
            if rule.id.hasSuffix("Red"), ids.contains(String(rule.id.dropLast(3)) + "Green"),
               ids.contains(String(rule.id.dropLast(3)) + "Blue") {
                let title = rule.name.replacingOccurrences(of: " red", with: "")
                result.append(.colour(prefix: String(rule.id.dropLast(3)), title: title))
            } else if rule.id.hasSuffix("Green") || rule.id.hasSuffix("Blue"),
                      ids.contains(String(rule.id.dropLast(rule.id.hasSuffix("Green") ? 5 : 4)) + "Red") {
                continue
            } else {
                result.append(.plain(rule))
            }
        }
        return result
    }

    private func numbers(of effect: EffectInstance, _ rule: EffectParameterDefinition) -> [Double] {
        let time = model.currentTime
        switch effect.parameters[rule.id] {
        case .scalar(let track)?:
            return [track.value(at: time)]
        case .vector(let track)?:
            let v = track.value(at: time)
            return [v.x, v.y]
        case nil:
            switch rule.kind {
            case .scalar(_, _, let defaultValue): return [defaultValue]
            case .choice(_, let defaultIndex): return [Double(defaultIndex)]
            case .vector(let defaultValue): return [defaultValue.x, defaultValue.y]
            }
        }
    }

    private func parameterSection(effect: EffectInstance, definition: EffectDefinition) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(definition.name) settings")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            if effect.effectID == "optical-flow-slow-motion" {
                if let layer = model.selectedLayer, case .video = layer.kind {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Video speed")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text(String(format: "%.2g×", layer.playbackSpeed))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(Theme.textSecondary)
                        }
                        RulerValueControl(value: Binding(
                            get: { layer.playbackSpeed },
                            set: { model.setPlaybackSpeed(layer.id, to: $0) }
                        ), range: 0.25...1.0, step: 0.05, suffix: "×")
                        Text("Slows the source video and uses optical-flow frame synthesis during export. Preview scrubbing uses normal frame decoding to stay responsive; slower speeds can take longer to export.")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                } else {
                    Text("This is a video-only effect. Select a video layer to adjust its playback speed.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            } else if definition.parameters.isEmpty {
                Text("This effect has no adjustable parameters.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(items(for: definition)) { item in
                switch item {
                case .plain(let rule): settingRow(effect: effect, rule: rule)
                case .colour(let prefix, let title): colourRow(effect: effect, prefix: prefix, title: title)
                }
            }
        }
    }

    @ViewBuilder
    private func settingRow(effect: EffectInstance, rule: EffectParameterDefinition) -> some View {
        let current = numbers(of: effect, rule)
        switch rule.kind {
        case .scalar(let minimum, let maximum, _):
            let value = current.first ?? minimum
            VStack(alignment: .leading, spacing: 0) {
                Text(rule.name)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                RulerValueControl(value: Binding(get: { value },
                                                 set: { model.setEffectValues(effect.id, [rule.id: [$0]], coalescing: true) }),
                                  range: minimum...maximum, step: max((maximum - minimum) / 1000, 0.001))
                    .accessibilityLabel(rule.name)
            }
        case .choice(let options, _):
            let selected = Int((current.first ?? 0).rounded())
            HStack {
                Text(rule.name)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Picker(rule.name, selection: Binding(get: { selected },
                                                     set: { model.setEffectValues(effect.id, [rule.id: [Double($0)]], coalescing: false) })) {
                    ForEach(options.indices, id: \.self) { index in
                        Text(options[index]).tag(index)
                    }
                }
                .pickerStyle(.menu)
            }
        case .vector:
            let x = current.count > 0 ? current[0] : 0
            let y = current.count > 1 ? current[1] : 0
            VStack(alignment: .leading, spacing: 4) {
                Text(rule.name)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 10) {
                    NumberField(title: "X", value: x) { model.setEffectValues(effect.id, [rule.id: [$0, y]], coalescing: false) }
                    NumberField(title: "Y", value: y) { model.setEffectValues(effect.id, [rule.id: [x, $0]], coalescing: false) }
                }
            }
        }
    }

    private func colourRow(effect: EffectInstance, prefix: String, title: String) -> some View {
        func channel(_ suffix: String) -> Double {
            guard case .scalar(let track)? = effect.parameters[prefix + suffix] else { return 0 }
            return track.value(at: model.currentTime)
        }
        let binding = Binding<Color>(
            get: { Color(.sRGB, red: channel("Red"), green: channel("Green"), blue: channel("Blue"), opacity: 1) },
            set: { newColour in
                var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
                UIColor(newColour).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
                // One command for all three numbers, so it is a single undo step.
                model.setEffectValues(effect.id, [prefix + "Red": [Double(red)],
                                                  prefix + "Green": [Double(green)],
                                                  prefix + "Blue": [Double(blue)]], coalescing: true)
            })
        return ColorPicker(title, selection: binding, supportsOpacity: false)
            .font(.subheadline)
            .foregroundStyle(Theme.textPrimary)
    }
}

/// A visual library for browsing every catalogued effect. Effects without a processor remain
/// visible with a clear "Coming soon" label instead of disappearing from the library.
@MainActor
struct EffectBrowserSheet: View {
    let model: EditorModel

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var category: EffectCategory?
    @State private var showAvailableOnly = false

    private let columns = [GridItem(.adaptive(minimum: 155), spacing: 10)]

    private var categories: [EffectCategory] { EffectCategory.allCases }

    private var filtered: [EffectDefinition] {
        EffectRegistry.all.filter { item in
            (category == nil || item.category == category)
                && (!showAvailableOnly || EffectRegistry.isAvailable(id: item.id))
                && (search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || item.name.localizedCaseInsensitiveContains(search)
                    || EffectLibraryMetadata.summary(for: item).localizedCaseInsensitiveContains(search))
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    searchField
                    categoryPicker
                    HStack(spacing: 8) {
                        Text(category?.displayName ?? (showAvailableOnly ? "Ready to use" : "All effects"))
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text("\(filtered.count) effects")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                        ForEach(filtered) { definition in effectCard(definition) }
                    }
                    if filtered.isEmpty {
                        ContentUnavailableView("No effects found", systemImage: "slider.horizontal.3",
                                               description: Text("Try another search or category."))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                    }
                }
                .padding(16)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Effects Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(LinearGradient(colors: [Theme.accent, Theme.accent.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 54, height: 54)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Make it yours")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Browse, search and stack effects.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            HStack(spacing: 8) {
                Label("\(EffectRegistry.available.count) ready", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.success)
                Text("·")
                Label("\(EffectRegistry.all.count - EffectRegistry.available.count) coming soon", systemImage: "clock")
                    .foregroundStyle(Theme.textSecondary)
            }
            .font(.caption.weight(.medium))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
            TextField("Search effects or what they do", text: $search)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .autocorrectionDisabled()
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 13)
        .frame(height: 46)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    categoryChip("All", symbol: "square.grid.2x2.fill", selected: category == nil && !showAvailableOnly) {
                        category = nil; showAvailableOnly = false
                    }
                    categoryChip("Ready", symbol: "checkmark.circle.fill", selected: showAvailableOnly) {
                        category = nil; showAvailableOnly = true
                    }
                    ForEach(categories, id: \.self) { item in
                        categoryChip(item.displayName, symbol: EffectLibraryMetadata.categorySymbol(item), selected: category == item) {
                            category = item; showAvailableOnly = false
                        }
                    }
                }
            }
        }
    }

    private func categoryChip(_ title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(selected ? Color.white : Theme.textPrimary)
                .padding(.horizontal, 12)
                .frame(height: 35)
                .background(selected ? Theme.accent : Theme.surfaceRaised, in: Capsule())
                .overlay(Capsule().strokeBorder(selected ? Color.clear : Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func effectCard(_ definition: EffectDefinition) -> some View {
        let available = EffectRegistry.isAvailable(id: definition.id)
        return Button {
            guard available else { return }
            MotionStudioHaptics.selection()
            model.addEffect(definition.id)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(available ? Theme.accent.opacity(0.18) : Theme.surfaceRaised)
                        Image(systemName: EffectLibraryMetadata.symbol(for: definition))
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(available ? Theme.accent : Theme.textSecondary)
                    }
                    .frame(width: 42, height: 42)
                    Spacer(minLength: 4)
                    Image(systemName: available ? "plus.circle.fill" : "lock.circle")
                        .font(.system(size: 19))
                        .foregroundStyle(available ? Theme.accent : Theme.textSecondary)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(definition.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                    Text(EffectLibraryMetadata.summary(for: definition))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .topLeading)
                }
                HStack {
                    Text(definition.category.displayName)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    Text(available ? "READY" : "COMING SOON")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(0.4)
                        .foregroundStyle(available ? Theme.success : Theme.textSecondary)
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(available ? Theme.hairline : Theme.hairline.opacity(0.55), lineWidth: 1))
            .opacity(available ? 1 : 0.78)
        }
        .buttonStyle(.plain)
        .disabled(!available)
        .accessibilityLabel("\(definition.name). \(EffectLibraryMetadata.summary(for: definition)). \(available ? "Ready to add" : "Coming soon")")
    }
}
