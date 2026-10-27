# Feature Batch 4 — Media, Transform and Effects Foundation

## Implemented in source

- Expanded the Files importer to accept supported images, MOV/MP4-style video, audio and TTF/OTF font files, including multi-selection.
- Added security-scoped URL handling and file coordination for file-provider/iCloud copies on Apple platforms.
- Added video and audio layer kinds to the project model. Video layers can display a frame from the current composition time in the preview; they are still-frame rendered, not a fully real-time AVPlayer compositor.
- Added audio extraction from a selected video layer to an M4A file and creates a corresponding audio timeline clip, aligned to the video layer's in-point.
- Added editable text layers and registration/selection for imported TTF/OTF fonts.
- Added a dedicated Transform drag pad so the user can move a selected layer from the bottom inspector without covering the composition preview.
- Added Null Object creation, parent selection and cycle prevention for null parenting.
- Added current-frame PNG/JPEG export using the system share sheet.
- Added real processing for Chroma Key, Box Blur, Zoom Blur, deterministic Noise, CMYK Halftone Dots, Roughen Edges and procedural Random Displacement.
- Added tests for the new effect processors and null-parent validation.

## Known limitations (not complete yet)

- Video preview currently requests still frames at the playhead time; this is not a dedicated real-time video playback engine and may lag while frames are generated.
- Audio can be imported and extracted into a timeline clip, but synchronized audio playback/mixing, waveform display and audio-inclusive MP4 export are not implemented yet.
- PNG/JPEG export renders the current composition frame. MP4 composition export, export ETA/progress screen and batch export are not implemented yet.
- Text supports editable content and registered font selection. Full text styling, text animation, font weight/style controls and font embedding in exported video remain future work.
- Adjustment layers, editable vector pen paths, clipping masks, layer borders, advanced parenting controls, and a full custom Bézier graph editor are not implemented in this batch.
- Motion Blur, Lens Blur, Rays, Oscillate, Random Jitter and Flicker are still not connected to full working processing/animation logic. Random Displacement is a procedural displacement field; it does not yet accept a separate source map.

## Validation

- `swift test` in `MotionCore`: 234 tests pass.
- Swift parser pass across App, MotionCore sources and tests.
- `python scripts/check_repository.py`: passes; 168 effect catalogue names and 77 Swift files checked.
- No iOS/macOS SDK was available in the local environment, so an actual Xcode iOS build and device/iPad runtime test were not performed. Run the GitHub Actions iOS build before treating this ZIP as device-verified.
