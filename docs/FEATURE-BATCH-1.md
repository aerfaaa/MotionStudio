# Feature batch 1 — timeline and import foundation

This batch makes the existing editor easier to use while keeping the saved project model compatible.

## Included

- Import multiple image files from Files in one selection.
- Timeline horizontal scrolling and zoom (1×–12×), with the zoom preference remembered.
- Trim layer in/out points by dragging the clip's left/right handles. Edits snap to composition frames and are grouped into one undo step per drag.
- Add the missing `SideTab` declaration and the missing `Effects` tab entry that prevented `EditorScreen.swift` from compiling.
- Correct two pre-existing effect-command tests and add a regression test for coalesced timeline trimming.

## Validation

- `swift test --package-path MotionCore`: 231 tests passed on Linux.
- `python scripts/check_repository.py`: passed.
- The iOS app has **not** been built in this environment because SwiftUI/Xcode's iOS SDK is unavailable here. GitHub Actions must still validate the actual iOS target.

## Next development batches

1. Import audio and video as real timeline media, including duration metadata, synchronized playback and audio waveform rendering.
2. Implement an export pipeline, beginning with still-frame/PNG sequence output, then H.264 MP4 and GIF where supported.
3. Add `.cube` LUT import and grading controls.
4. Add effects such as motion blur, motion tile, directional blur, and displacement after the renderer supports them correctly.

Importing RAW photos/video will be evaluated separately because file recognition alone does not guarantee full decoding or performant editing.
