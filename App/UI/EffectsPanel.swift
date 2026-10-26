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
            if definition.parameters.isEmpty {
                Text("This effect has no settings.")
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
                HStack {
                    Text(rule.name)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text(String(format: "%.2f", value))
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                }
                Slider(value: Binding(get: { value },
                                      set: { model.setEffectValues(effect.id, [rule.id: [$0]], coalescing: true) }),
                       in: minimum...maximum,
                       onEditingChanged: { editing in if !editing { model.endEditGroup() } })
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

/// Choose an effect to add. Only effects whose processing is really connected are listed.
@MainActor
struct EffectBrowserSheet: View {
    let model: EditorModel

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var category: EffectCategory?

    private var categories: [EffectCategory] {
        EffectCategory.allCases.filter { category in EffectRegistry.available.contains(where: { $0.category == category }) }
    }

    private func results(in category: EffectCategory) -> [EffectDefinition] {
        EffectRegistry.available.filter { definition in
            definition.category == category
                && (search.isEmpty || definition.name.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            chip("All", isSelected: category == nil) { category = nil }
                            ForEach(categories, id: \.self) { item in
                                chip(item.displayName, isSelected: category == item) { category = item }
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
                ForEach(categories.filter { category == nil || $0 == category }, id: \.self) { item in
                    let found = results(in: item)
                    if !found.isEmpty {
                        Section(item.displayName) {
                            ForEach(found) { definition in
                                Button {
                                    model.addEffect(definition.id)
                                    dismiss()
                                } label: {
                                    HStack {
                                        Text(definition.name).foregroundStyle(Theme.textPrimary)
                                        Spacer()
                                        Image(systemName: "plus.circle").foregroundStyle(Theme.accent)
                                    }
                                    .frame(minHeight: 44)
                                }
                            }
                        }
                    }
                }
            }
            .overlay {
                if categories.allSatisfy({ results(in: $0).isEmpty }) {
                    Text("No effects match \"\(search)\".")
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .searchable(text: $search, prompt: "Search effects")
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Add effect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func chip(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : Theme.textPrimary)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(isSelected ? Theme.accent : Theme.surfaceRaised, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
