import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import MotionCore

private enum LowerTab: String, CaseIterable, Identifiable {
    case timeline = "Timeline"
    case properties = "Transform"
    case effects = "Effects"
    var id: String { rawValue }
}

private enum SideTab: String, CaseIterable, Identifiable {
    case properties = "Properties"
    case effects = "Effects"
    var id: String { rawValue }
}

/// The editing workspace. It rearranges itself for the space it is given:
/// - narrow screens (iPhone portrait, small iPad windows): preview on top, tabbed panel below
/// - short wide screens (iPhone landscape): preview beside a tabbed panel
/// - large wide screens (iPad): preview and timeline on the left, properties always visible on the right
@MainActor
struct EditorScreen: View {
    @State private var model: EditorModel
    @State private var tab: LowerTab = .timeline
    @Environment(\.scenePhase) private var scenePhase
    // The timeline panel's size is remembered between sessions.
    @AppStorage("timelinePanelFraction") private var panelFraction: Double = 0.55
    @AppStorage("timelineCollapsed") private var timelineCollapsed = false
    @AppStorage("showAlignmentGuides") private var showAlignmentGuides = true
    @State private var dragStartHeight: CGFloat?
    @State private var showingCompositionSettings = false
    @State private var sideTab: SideTab = .properties
    @State private var showingImportChoice = false
    @State private var showingPhotoPicker = false
    @State private var showingFileImporter = false
    @State private var photoItem: PhotosPickerItem?
    let onClose: () -> Void

    init(model: EditorModel, onClose: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.onClose = onClose
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 8) {
                topBar
                workspace(size: geometry.size)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(Theme.background.ignoresSafeArea())
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.saveNow() }
        }
        .sheet(isPresented: $showingCompositionSettings) {
            CompositionSettingsSheet(model: model)
        }
        .confirmationDialog("Import images", isPresented: $showingImportChoice, titleVisibility: .visible) {
            Button("Photo Library") { showingPhotoPicker = true }
            Button("Files") { showingFileImporter = true }
            Button("Cancel", role: .cancel) {}
        }
        .photosPicker(isPresented: $showingPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            Task { await importPhoto(item) }
        }
        .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.image],
                      allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                model.importImages(fromFiles: urls)
            case .failure(let error):
                model.lastError = "The file could not be opened. \(error.localizedDescription)"
            }
        }
        .overlay {
            if model.isImporting {
                ProgressView("Importing…")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .alert("Something went wrong",
               isPresented: .constant(model.lastError != nil),
               actions: { Button("OK") { model.lastError = nil } },
               message: { Text(model.lastError ?? "") })
    }

    // MARK: Layouts

    @ViewBuilder
    private func workspace(size: CGSize) -> some View {
        if size.width >= 900 && size.height >= 560 {
            tabletLayout(size: size)
        } else if size.width > size.height && size.height < 560 {
            landscapePhoneLayout(size: size)
        } else {
            stackedLayout(size: size)
        }
    }

    private func stackedLayout(size: CGSize) -> some View {
        let available = max(300, size.height - 70)          // what is left under the top bar
        let handleHeight: CGFloat = 28
        let collapsedHeight: CGFloat = 64                    // just the Timeline / Properties tabs
        let expandedHeight = min(max(CGFloat(panelFraction) * available, 150), available * 0.75)
        let panelHeight = timelineCollapsed ? collapsedHeight : expandedHeight
        let previewHeight = max(120, available - panelHeight - handleHeight - 8)
        return VStack(spacing: 4) {
            previewBlock
                .frame(height: previewHeight)
            resizeHandle(available: available, currentHeight: panelHeight)
            tabbedPanel(showsContent: !timelineCollapsed)
                .frame(height: panelHeight)
        }
    }

    private func landscapePhoneLayout(size: CGSize) -> some View {
        HStack(spacing: 10) {
            previewBlock
            tabbedPanel(showsContent: true)
                .frame(width: max(320, size.width * 0.44))
        }
    }

    private func tabletLayout(size: CGSize) -> some View {
        let available = max(300, size.height - 70)
        let expandedHeight = min(max(CGFloat(panelFraction) * available, 160), available * 0.7)
        let panelHeight: CGFloat = timelineCollapsed ? 0 : expandedHeight
        return HStack(spacing: 12) {
            VStack(spacing: 4) {
                previewBlock
                resizeHandle(available: available, currentHeight: panelHeight)
                if !timelineCollapsed {
                    TimelinePanel(model: model)
                        .panel()
                        .frame(height: panelHeight)
                }
            }
            VStack(spacing: 0) {
                Picker("Side panel", selection: $sideTab) {
                    ForEach(SideTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(10)
                switch sideTab {
                case .properties: InspectorView(model: model)
                case .effects: EffectsPanel(model: model)
                }
            }
            .panel()
            .frame(width: 340)
        }
    }

    /// The bar between the preview and the timeline. Drag it up or down to resize the timeline,
    /// or tap the arrow to collapse and expand it.
    private func resizeHandle(available: CGFloat, currentHeight: CGFloat) -> some View {
        HStack {
            Spacer()
            Capsule()
                .fill(Theme.textSecondary.opacity(0.5))
                .frame(width: 40, height: 5)
            Spacer()
        }
        .overlay(alignment: .trailing) {
            Button { timelineCollapsed.toggle() } label: {
                Image(systemName: timelineCollapsed ? "chevron.up" : "chevron.down")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 48, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(timelineCollapsed ? "Expand timeline" : "Collapse timeline")
        }
        .frame(height: 28)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    if dragStartHeight == nil { dragStartHeight = currentHeight }
                    let newHeight = (dragStartHeight ?? currentHeight) - value.translation.height
                    if newHeight < 110 {
                        timelineCollapsed = true
                    } else {
                        timelineCollapsed = false
                        panelFraction = Double(min(max(newHeight / available, 0.2), 0.75))
                    }
                }
                .onEnded { _ in dragStartHeight = nil }
        )
        .accessibilityLabel("Timeline size")
        .accessibilityHint("Drag up or down to resize the timeline.")
    }

    private var previewBlock: some View {
        VStack(spacing: 4) {
            PreviewView(model: model, showAlignmentGuides: showAlignmentGuides)
                .clipShape(RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
            TransportBar(model: model)
        }
    }

    private func tabbedPanel(showsContent: Bool) -> some View {
        VStack(spacing: 0) {
            Picker("Panel", selection: $tab) {
                ForEach(LowerTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(10)

            if showsContent {
                switch tab {
                case .timeline:
                    TimelinePanel(model: model)
                case .properties:
                    InspectorView(model: model)
                case .effects:
                    EffectsPanel(model: model)
                }
            }
        }
        .panel()
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 0) {
            IconButton(systemName: "chevron.left", label: "Back to projects") { close() }

            VStack(spacing: 1) {
                Text(model.project.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text("\(model.composition.width)×\(model.composition.height), \(model.composition.frameRate.displayName)")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Circle()
                        .fill(saveColour)
                        .frame(width: 6, height: 6)
                        .accessibilityLabel(saveDescription)
                }
            }
            .frame(maxWidth: .infinity)

            IconButton(systemName: "arrow.uturn.backward", label: model.undoName.map { "Undo \($0)" } ?? "Undo") {
                model.undo()
            }
            .opacity(model.canUndo ? 1 : 0.35)
            .disabled(!model.canUndo)

            IconButton(systemName: "arrow.uturn.forward", label: model.redoName.map { "Redo \($0)" } ?? "Redo") {
                model.redo()
            }
            .opacity(model.canRedo ? 1 : 0.35)
            .disabled(!model.canRedo)

            IconButton(systemName: showAlignmentGuides ? "viewfinder" : "viewfinder.circle",
                       label: showAlignmentGuides ? "Turn alignment guides off" : "Turn alignment guides on",
                       isActive: showAlignmentGuides) {
                showAlignmentGuides.toggle()
            }

            IconButton(systemName: "photo.badge.plus", label: "Import images") { showingImportChoice = true }

            addMenu
        }
        .frame(height: 48)
    }

    private var addMenu: some View {
        Menu {
            Button { model.addLayer(.rectangle) } label: { Label("Rectangle", systemImage: "rectangle") }
            Button { model.addLayer(.ellipse) } label: { Label("Ellipse", systemImage: "circle") }
            Button { model.addLayer(.solid) } label: { Label("Solid", systemImage: "square.fill") }
            Divider()
            Button { model.duplicateSelected() } label: { Label("Duplicate layer", systemImage: "plus.square.on.square") }
                .disabled(model.selectedLayerID == nil)
            Button(role: .destructive) { model.deleteSelected() } label: { Label("Delete layer", systemImage: "trash") }
                .disabled(model.selectedLayerID == nil)
            Divider()
            Button { showingCompositionSettings = true } label: {
                Label("Composition settings", systemImage: "slider.horizontal.3")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 40, height: 40)
                .background(Theme.accent, in: Circle())
                .frame(width: 48, height: 48)
        }
        .accessibilityLabel("Add layer")
    }

    private var saveColour: Color {
        switch model.saveState {
        case .saved: return Theme.success
        case .unsaved: return Theme.keyframe
        case .failed: return Theme.danger
        }
    }

    private var saveDescription: String {
        switch model.saveState {
        case .saved: return "Saved"
        case .unsaved: return "Saving"
        case .failed: return "Not saved"
        }
    }

    /// Loads a photo chosen in the Photos library and imports it. Cancelling the picker does nothing.
    private func importPhoto(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                model.lastError = "The photo could not be loaded."
                return
            }
            let fileExtension = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
            model.importImage(data: data, fileExtension: fileExtension, baseName: "Photo")
        } catch {
            model.lastError = "The photo could not be loaded. \(error.localizedDescription)"
        }
    }

    private func close() {
        model.shutdown()
        onClose()
    }
}
