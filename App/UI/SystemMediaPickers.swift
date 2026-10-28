import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

/// Uses UIKit's document picker with `asCopy: true`, so Files/iCloud providers hand
/// the editor an app-owned copy instead of a short-lived security-scoped URL.
struct SystemDocumentMediaPicker: UIViewControllerRepresentable {
    let onPicked: ([URL]) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked, onCancel: onCancel) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.image, .movie, .video, .audio, .font, .data],
            asCopy: true
        )
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPicked: ([URL]) -> Void
        let onCancel: () -> Void
        init(onPicked: @escaping ([URL]) -> Void, onCancel: @escaping () -> Void) {
            self.onPicked = onPicked
            self.onCancel = onCancel
        }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPicked(urls)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}

/// Photos picker fallback that materialises the selected item immediately. This avoids depending
/// on the lifetime of a Photos/iCloud provider URL after its callback returns.
struct SystemPhotoMediaPicker: UIViewControllerRepresentable {
    let onPicked: ([URL]) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked, onCancel: onCancel) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .any(of: [.images, .videos])
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPicked: ([URL]) -> Void
        let onCancel: () -> Void
        init(onPicked: @escaping ([URL]) -> Void, onCancel: @escaping () -> Void) {
            self.onPicked = onPicked
            self.onCancel = onCancel
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            // SwiftUI owns this controller through a sheet. Let the parent close that sheet after
            // the callback; manually dismissing here can dismiss the editor's full-screen cover too.
            guard let provider = results.first?.itemProvider else {
                onCancel()
                return
            }
            let identifiers = provider.registeredTypeIdentifiers
            let selectedType = identifiers.first { id in
                guard let type = UTType(id) else { return false }
                return type.conforms(to: .movie) || type.conforms(to: .video) || type.conforms(to: .image)
            }
            guard let typeIdentifier = selectedType else {
                DispatchQueue.main.async { self.onPicked([]) }
                return
            }
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { sourceURL, error in
                guard let sourceURL else {
                    DispatchQueue.main.async {
                        self.onPicked([])
                    }
                    return
                }
                let ext = sourceURL.pathExtension.isEmpty
                    ? (UTType(typeIdentifier)?.preferredFilenameExtension ?? "dat")
                    : sourceURL.pathExtension
                let destination = FileManager.default.temporaryDirectory
                    .appendingPathComponent("MotionStudio-Photos-\(UUID().uuidString).\(ext)")
                do {
                    try FileManager.default.copyItem(at: sourceURL, to: destination)
                    DispatchQueue.main.async { self.onPicked([destination]) }
                } catch {
                    DispatchQueue.main.async { self.onPicked([]) }
                }
            }
        }
    }
}
