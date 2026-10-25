import SwiftUI
import MotionCore

/// One open editing session. Wrapping the model lets SwiftUI present it full screen.
struct EditorSession: Identifiable {
    let id = UUID()
    let model: EditorModel
}

/// The first screen: your projects, and a way to make a new one.
@MainActor
struct RootView: View {
    let store: ProjectStore

    @State private var session: EditorSession?
    @State private var showingNewProject = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if store.entries.isEmpty {
                    emptyState
                } else {
                    projectList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Projects")
            .toolbar {
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

    private var projectList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(store.entries) { entry in
                    Button { open(entry) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.name)
                                    .font(.headline)
                                    .foregroundStyle(Theme.textPrimary)
                                Text(entry.modified.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity)
                        .panel()
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) { store.delete(entry) } label: {
                            Label("Delete project", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private func open(_ entry: ProjectEntry) {
        do {
            let project = try store.load(entry)
            session = EditorSession(model: EditorModel(project: project, folderURL: entry.url))
        } catch {
            errorMessage = error.localizedDescription
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
                    Picker("Size", selection: $settings.resolution) {
                        ForEach(ResolutionPreset.all) { preset in
                            Text(preset.label).tag(preset)
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
                    Text("The composition size and frame rate are saved in the project. They do not depend on your screen.")
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
                }
            }
        }
    }
}
