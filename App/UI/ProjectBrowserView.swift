import SwiftUI
import MotionCore

/// One open editing session. Wrapping the model lets SwiftUI present it full screen.
struct EditorSession: Identifiable {
    let id = UUID()
    let model: EditorModel
}

/// The first screen: your projects as cards with a preview, and a way to make a new one.
@MainActor
struct RootView: View {
    let store: ProjectStore

    @State private var session: EditorSession?
    @State private var showingNewProject = false
    @State private var showingSettings = false
    @State private var errorMessage: String?
    @State private var renaming: ProjectEntry?
    @State private var renameText = ""
    @State private var deleting: ProjectEntry?

    var body: some View {
        NavigationStack {
            Group {
                if store.entries.isEmpty {
                    emptyState
                } else {
                    projectGrid
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Projects")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingNewProject = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("New project")
                }
            }
        }
        .fullScreenCover(item: $session) { current in
            EditorScreen(model: current.model) {
                session = nil
                store.reload()
            }
        }
        .sheet(isPresented: $showingNewProject) {
            NewProjectSheet { settings in
                create(settings)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsSheet()
        }
        .alert("Rename project",
               isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }),
               actions: {
                   TextField("Name", text: $renameText)
                   Button("Cancel", role: .cancel) { renaming = nil }
                   Button("Rename") {
                       if let entry = renaming { rename(entry, to: renameText) }
                       renaming = nil
                   }
               })
        .confirmationDialog("Delete this project?",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible,
                            presenting: deleting) { entry in
            Button("Delete \(entry.name)", role: .destructive) { store.delete(entry) }
        } message: { entry in
            Text("\(entry.name) and its media will be removed from this device. This cannot be undone.")
        }
        .alert("Something went wrong",
               isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }),
               actions: { Button("OK") { errorMessage = nil } },
               message: { Text(errorMessage ?? "") })
        .task {
            // `-demo` is used by the automatic screenshot job on GitHub.
            if ProcessInfo.processInfo.arguments.contains("-demo") {
                do {
                    let result = try store.createDemo()
                    session = EditorSession(model: EditorModel(project: result.project, folderURL: result.entry.url))
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: Pieces

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "film.stack")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(Theme.textSecondary)
            Text("No projects yet")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Create a project to start placing layers and animating them.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Button { showingNewProject = true } label: {
                Text("New project")
                    .font(.headline)
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 22)
                    .frame(height: 48)
                    .background(Theme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(32)
    }

    private var projectGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Recent")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 4)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 14)], spacing: 14) {
                    ForEach(store.entries) { entry in
                        card(for: entry)
                    }
                }
            }
            .padding(16)
        }
    }

    private func card(for entry: ProjectEntry) -> some View {
        Button { open(entry) } label: {
            VStack(alignment: .leading, spacing: 10) {
                ProjectThumbnail(entry: entry)
                    .aspectRatio(1.6, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(entry.modified.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .panel()
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            Menu {
                actions(for: entry)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 34, height: 34)
                    .background(Color.black.opacity(0.45), in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .padding(10)
            .accessibilityLabel("Project options for \(entry.name)")
        }
        .contextMenu { actions(for: entry) }
    }

    @ViewBuilder
    private func actions(for entry: ProjectEntry) -> some View {
        Button {
            renameText = entry.name
            renaming = entry
        } label: { Label("Rename", systemImage: "pencil") }
        Button { duplicate(entry) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
        Button(role: .destructive) { deleting = entry } label: { Label("Delete", systemImage: "trash") }
    }

    // MARK: Actions

    private func open(_ entry: ProjectEntry) {
        do {
            let project = try store.load(entry)
            session = EditorSession(model: EditorModel(project: project, folderURL: entry.url))
        } catch {
            errorMessage = "\(entry.name) could not be opened. \(error.localizedDescription)"
        }
    }

    private func create(_ settings: NewProjectSettings) {
        do {
            let result = try store.create(settings)
            let newSession = EditorSession(model: EditorModel(project: result.project, folderURL: result.entry.url))
            // iOS cannot show the editor while the New Project sheet is still closing, so wait a moment.
            Task {
                try? await Task.sleep(nanoseconds: 450_000_000)
                session = newSession
            }
        } catch {
            errorMessage = "The project could not be created. \(error.localizedDescription)"
        }
    }

    private func rename(_ entry: ProjectEntry, to name: String) {
        do { try store.rename(entry, to: name) } catch { errorMessage = "Renaming failed. \(error.localizedDescription)" }
    }

    private func duplicate(_ entry: ProjectEntry) {
        do { try store.duplicate(entry) } catch { errorMessage = "Duplicating failed. \(error.localizedDescription)" }
    }
}

/// A small picture of the project, drawn from its saved file with the same renderer as the editor.
private struct ProjectThumbnail: View {
    let entry: ProjectEntry
    @State private var frame: ResolvedFrame?
    @State private var failed = false

    var body: some View {
        ZStack {
            Theme.surfaceRaised
            if let frame {
                Canvas { context, size in
                    let viewport = Viewport(compWidth: Double(frame.width), compHeight: Double(frame.height),
                                            viewWidth: Double(size.width), viewHeight: Double(size.height))
                    CanvasRenderer.draw(frame: frame, selectedLayerID: nil, viewport: viewport, context: context)
                }
            } else if failed {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(Theme.danger)
            }
        }
        .task(id: entry) {
            do {
                let project = try ProjectFile.load(fromFolder: entry.url)
                let composition = project.rootComposition
                // A frame from the middle shows more than the very first frame usually does.
                frame = Evaluator.resolve(composition, frame: max(0, composition.frameCount / 2))
                failed = false
            } catch {
                frame = nil
                failed = true
            }
        }
        .accessibilityHidden(true)
    }
}

/// Settings: appearance for now.
@MainActor
struct SettingsSheet: View {
    @AppStorage(AppearanceSetting.storageKey) private var appearanceName = AppearanceSetting.system.rawValue
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Appearance", selection: $appearanceName) {
                        ForEach(AppearanceSetting.allCases) { setting in
                            Text(setting.title).tag(setting.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("System follows your device setting.")
                }
                Section("Your projects") {
                    Text("Projects are saved on this device. Open the Files app, then On My iPhone or On My iPad, then Motion Studio, then Projects.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Choose a name, size, frame rate and length. The frame rate belongs to the composition
/// and has nothing to do with the screen the project is edited on.
@MainActor
struct NewProjectSheet: View {
    let onCreate: (NewProjectSettings) -> Void

    @State private var settings = NewProjectSettings()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Project name", text: $settings.name)
                }
                Section {
                    if !settings.useCustomSize {
                        Picker("Size", selection: $settings.resolution) {
                            ForEach(ResolutionPreset.all) { preset in
                                Text(preset.label).tag(preset)
                            }
                        }
                    }
                    Toggle("Custom size", isOn: $settings.useCustomSize)
                    if settings.useCustomSize {
                        HStack {
                            Text("Width")
                            Spacer()
                            TextField("Width", value: $settings.customWidth, format: .number.grouping(.never))
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                        }
                        HStack {
                            Text("Height")
                            Spacer()
                            TextField("Height", value: $settings.customHeight, format: .number.grouping(.never))
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                        }
                    }
                    Picker("Frame rate", selection: $settings.frameRate) {
                        ForEach(FrameRateOption.all) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    Picker("Length", selection: $settings.durationSeconds) {
                        ForEach([3.0, 5.0, 10.0, 30.0, 60.0], id: \.self) { seconds in
                            Text("\(Int(seconds)) seconds").tag(seconds)
                        }
                    }
                } header: {
                    Text("Composition")
                } footer: {
                    Text("The composition size and frame rate are saved in the project. They do not depend on your screen. Custom sizes can be \(SetCompositionSettings.minimumSize) to \(SetCompositionSettings.maximumSize) pixels.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("New project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onCreate(settings)
                        dismiss()
                    }
                    .disabled(!settings.isValid)
                }
            }
        }
    }
}
