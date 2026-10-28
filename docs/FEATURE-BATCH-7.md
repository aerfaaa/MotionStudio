# Feature Batch 7 — iPad import and editor usability

## Changes

- Replaced the SwiftUI `PhotosPicker` import route with a UIKit `PHPickerViewController` wrapper. It materialises the selected photo or video into an app temporary file before the provider callback returns, then hands that local file to the existing media import pipeline.
- Replaced SwiftUI `.fileImporter` with `UIDocumentPickerViewController(forOpeningContentTypes:asCopy: true)`, allowing multi-select and asking iPadOS to provide app-owned copies from Files/iCloud providers.
- Kept media copying into project-owned storage, so projects do not rely on picker URLs remaining available.
- Simplified the editor toolbar: media import and new-layer creation are grouped under one labelled **Add** menu; export actions are grouped under Export, and alignment guides live in the export/view menu rather than consuming a permanent toolbar button.

## Verification and limitations

- MotionCore unit tests pass on Linux.
- Swift syntax parser and repository checks pass.
- This environment cannot build the UIKit app with Xcode or test the picker on a physical iPad. A device build remains required. If import still fails, capture the error shown by the app and the GitHub Actions Xcode build log.
