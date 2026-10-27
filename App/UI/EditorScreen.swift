import SwiftUI
import UniformTypeIdentifiers
import UIKit
import AVFoundation
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
    @State private var showingPhotoPicker = false
    @State private var showingFileImporter = false
    @State private var isExportingVideo = false
    @State private var videoExportProgress = 0.0
    @State private var showingShareSheet = false
    @State private var exportedURL: URL?
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
        .sheet(isPresented: $showingShareSheet) {
            if let exportedURL { ActivityShareSheet(items: [exportedURL]) }
        }
        .sheet(isPresented: $showingPhotoPicker) {
            SystemPhotoMediaPicker { urls in
                showingPhotoPicker = false
                guard !urls.isEmpty else {
                    model.lastError = "Photos could not provide that media. Try saving it to Files first, then use Add > Files."
                    return
                }
                model.importMedia(fromFiles: urls)
            } onCancel: {
                showingPhotoPicker = false
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showingFileImporter) {
            SystemDocumentMediaPicker { urls in
                showingFileImporter = false
                guard !urls.isEmpty else { return }
                model.importMedia(fromFiles: urls)
            } onCancel: {
                showingFileImporter = false
            }
            .ignoresSafeArea()
        }
        .overlay {
            if model.isImporting {
                ProgressView("Importing…")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else if isExportingVideo {
                VStack(spacing: 10) {
                    ProgressView(value: videoExportProgress)
                    Text("Exporting video · \(Int(videoExportProgress * 100))%")
                        .font(.footnote.weight(.medium))
                }
                .padding(24)
                .frame(maxWidth: 300)
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

            Menu {
                Section("Export") {
                    Button { exportCurrentFrame(as: .png) } label: { Label("Frame as PNG", systemImage: "photo") }
                    Button { exportCurrentFrame(as: .jpeg) } label: { Label("Frame as JPEG", systemImage: "photo.on.rectangle") }
                    Button { Task { await exportVideo() } } label: { Label("Video as MP4", systemImage: "film") }
                        .disabled(isExportingVideo || model.isImporting)
                }
                Section("View") {
                    Button { showAlignmentGuides.toggle() } label: {
                        Label(showAlignmentGuides ? "Hide alignment guides" : "Show alignment guides",
                              systemImage: showAlignmentGuides ? "viewfinder.circle" : "viewfinder")
                    }
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 40, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Export current composition frame")

            addMenu
        }
        .frame(height: 48)
        .padding(.horizontal, 7)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.hairline.opacity(0.9), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 14, y: 5)
    }

    private var addMenu: some View {
        Menu {
            Section("Import media") {
                Button { showingPhotoPicker = true } label: { Label("From Photos", systemImage: "photo.on.rectangle") }
                Button { showingFileImporter = true } label: { Label("From Files", systemImage: "folder") }
            }
            Section("New layer") {
                Button { model.addLayer(.rectangle) } label: { Label("Rectangle", systemImage: "rectangle") }
                Button { model.addLayer(.ellipse) } label: { Label("Ellipse", systemImage: "circle") }
                Button { model.addLayer(.solid) } label: { Label("Solid", systemImage: "square.fill") }
                Button { model.addLayer(.text) } label: { Label("Text", systemImage: "textformat") }
                Button { model.addLayer(.null) } label: { Label("Null Object", systemImage: "point.3.connected.trianglepath.dotted") }
            }
            Section("Selected layer") {
                Button { model.duplicateSelected() } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                    .disabled(model.selectedLayerID == nil)
                Button(role: .destructive) { model.deleteSelected() } label: { Label("Delete", systemImage: "trash") }
                    .disabled(model.selectedLayerID == nil)
                Button { showingCompositionSettings = true } label: {
                    Label("Composition settings", systemImage: "slider.horizontal.3")
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold))
                Text("Add")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 13)
            .frame(height: 40)
            .background(LinearGradient(colors: [Theme.accent, Theme.accent.opacity(0.78)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(.white.opacity(0.22), lineWidth: 1))
            .frame(minWidth: 48, minHeight: 48)
        }
        .accessibilityLabel("Add or import")
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

    private enum FrameExportFormat { case png, jpeg }

    @MainActor
    private func exportCurrentFrame(as format: FrameExportFormat) {
        let frame = model.resolvedFrame
        let width = CGFloat(model.composition.width)
        let height = CGFloat(model.composition.height)
        let provided = model.images.provideAll(for: frame, exportQuality: true)
        let stillLoading = provided.values.contains { item in
            if case .loading = item { return true }
            return false
        }
        let missingMedia = provided.values.contains { item in
            if case .missing = item { return true }
            return false
        }
        if stillLoading || model.images.isBusy {
            model.lastError = "Media or effects are still preparing for export. Wait for the preview to finish loading, then try again."
            return
        }
        if missingMedia {
            model.lastError = "One or more image/video files could not be read. Fix the missing media before exporting."
            return
        }

        let content = Canvas { context, size in
            let viewport = Viewport(compWidth: Double(model.composition.width),
                                    compHeight: Double(model.composition.height),
                                    viewWidth: size.width, viewHeight: size.height)
            CanvasRenderer.draw(frame: frame, selectedLayerID: nil, viewport: viewport,
                                context: context, images: provided)
        }
        .frame(width: width, height: height)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        guard let image = renderer.uiImage else {
            model.lastError = "The current frame could not be rendered for export."
            return
        }
        let data: Data?
        let ext: String
        switch format {
        case .png: data = image.pngData(); ext = "png"
        case .jpeg: data = image.jpegData(compressionQuality: 0.95); ext = "jpg"
        }
        guard let data else {
            model.lastError = "The frame could not be encoded."
            return
        }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("MotionStudio-Frame-\(UUID().uuidString).\(ext)")
        do {
            try data.write(to: destination, options: .atomic)
            exportedURL = destination
            showingShareSheet = true
        } catch {
            model.lastError = "The frame could not be saved: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func exportVideo() async {
        guard !isExportingVideo else { return }
        isExportingVideo = true
        videoExportProgress = 0
        let originalFrame = model.currentFrame
        do {
            let url = try await VideoFrameExporter.export(
                width: model.composition.width,
                height: model.composition.height,
                frameRate: model.composition.frameRate,
                frameCount: model.frameCount,
                layers: model.composition.layers,
                assets: model.project.assets,
                projectFolder: model.folderURL,
                frameProvider: { index in
                    model.seek(toFrame: index)
                    // Re-request frames while source loading/effects are running. Do not export a
                    // stale previous frame just because the preview cache is still busy.
                    for _ in 0..<400 {
                        let frame = model.resolvedFrame
                        let supplied = model.images.provideAll(for: frame, exportQuality: true)
                        let waiting = supplied.values.contains { item in
                            if case .loading = item { return true }
                            return false
                        }
                        if !waiting && !model.images.isBusy { break }
                        try await Task.sleep(for: .milliseconds(15))
                    }
                    let frame = model.resolvedFrame
                    let supplied = model.images.provideAll(for: frame, exportQuality: true)
                    if supplied.values.contains(where: { if case .loading = $0 { return true }; return false }) || model.images.isBusy {
                        throw VideoExportError.frameNotReady(index)
                    }
                    if supplied.values.contains(where: { if case .missing = $0 { return true }; return false }) {
                        throw VideoExportError.renderFailed(index)
                    }
                    let width = CGFloat(model.composition.width)
                    let height = CGFloat(model.composition.height)
                    let content = Canvas { context, _ in
                        CanvasRenderer.draw(frame: frame, selectedLayerID: nil,
                                            viewport: Viewport(compWidth: Double(width), compHeight: Double(height),
                                                               viewWidth: Double(width), viewHeight: Double(height)),
                                            context: context, images: supplied)
                    }.frame(width: width, height: height)
                    let renderer = ImageRenderer(content: content)
                    renderer.scale = 1
                    guard let image = renderer.uiImage else { throw VideoExportError.renderFailed(index) }
                    return image
                },
                progress: { value in videoExportProgress = value }
            )
            exportedURL = url
            showingShareSheet = true
        } catch {
            model.lastError = "Video export failed: \(error.localizedDescription)"
        }
        model.seek(toFrame: originalFrame)
        isExportingVideo = false
    }

    private func close() {
        model.shutdown()
        onClose()
    }
}

