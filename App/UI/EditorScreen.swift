            } label: {
                Label("Ellipse", systemImage: "circle")
            }

            Button {
                model.addLayer(.solid)
            } label: {
                Label("Solid", systemImage: "square.fill")
            }

            Divider()

            Button {
                model.duplicateSelected()
            } label: {
                Label("Duplicate layer", systemImage: "plus.square.on.square")
            }
            .disabled(model.selectedLayerID == nil)

            Button(role: .destructive) {
                model.deleteSelected()
            } label: {
                Label("Delete layer", systemImage: "trash")
            }
            .disabled(model.selectedLayerID == nil)

            Divider()

            Button {
                showingCompositionSettings = true
            } label: {
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
        case .saved:
            return Theme.success
        case .unsaved:
            return Theme.keyframe
        case .failed:
            return Theme.danger
        }
    }

    private var saveDescription: String {
        switch model.saveState {
        case .saved:
            return "Saved"
        case .unsaved:
            return "Saving"
        case .failed:
            return "Not saved"
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
            model.importImage(
                data: data,
                fileExtension: fileExtension,
                baseName: "Photo"
            )
        } catch {
            model.lastError = "The photo could not be loaded. \(error.localizedDescription)"
        }
    }

    private func close() {
        model.shutdown()
        onClose()
    }
}

/// Owns the Photos picker presentation independently of EditorScreen's other presentations.
private struct PhotoPickerPresenter: View {
    @Binding var isPresented: Bool
    @Binding var selection: PhotosPickerItem?

    var body: some View {
        Color.clear
            .photosPicker(
                isPresented: $isPresented,
                selection: $selection,
                matching: .images
            )
    }
}

/// Owns the Files importer presentation independently of the Photos picker.
private struct ImageFileImporterPresenter: View {
    @Binding var isPresented: Bool
    let onCompletion: (Result<[URL], Error>) -> Void

    var body: some View {
        Color.clear
            .fileImporter(
                isPresented: $isPresented,
                allowedContentTypes: [.image],
                allowsMultipleSelection: false,
                onCompletion: onCompletion
            )
    }
}

