import Foundation
import Photos
import UIKit

/// Saves finished exports to the user's Photos library using add-only access.
enum ExportedMediaSaver {
    enum SaveError: LocalizedError {
        case permissionDenied
        case libraryWriteFailed

        var errorDescription: String? {
            switch self {
            case .permissionDenied: return "MotionStudio does not have permission to add media to Photos. Enable it in Settings, then try again."
            case .libraryWriteFailed: return "Photos could not save the exported media. The exported file is still available to share."
            }
        }
    }

    static func saveVideo(at url: URL) async throws {
        try await save { PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url) }
    }

    static func saveImage(at url: URL) async throws {
        try await save { PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url) }
    }

    private static func save(change: @escaping () -> Void) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw SaveError.permissionDenied }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges(change) { success, error in
                if success { continuation.resume() }
                else { continuation.resume(throwing: error ?? SaveError.libraryWriteFailed) }
            }
        }
    }
}
