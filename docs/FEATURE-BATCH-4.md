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


## Follow-up fixes — Batch 5 (2026-10-27)

The source was updated after hands-on testing feedback. This is a code change, not a claim that an iPad build was tested.

### Added/fixed in this pass

- Text and shape/solid colour controls now include a native colour picker with opacity, not just preset swatches.
- Transform drag-pad sensitivity is adjustable and remembered between sessions (default 25%).
- Noise changes its seed at 12 fps while previewing/exporting, so it is animated rather than frozen; this is intentionally slower than display refresh to limit CPU work.
- Preview processing size is capped at 768 px on the longest side to reduce the worst CPU spikes.
- Timeline trim handles provide light haptic feedback when the snapped frame changes.
- Removed the duplicated per-number-field keyboard “Done” accessory buttons.
- Photos picker accepts both images and videos; video uses a file transfer instead of loading the whole movie into memory.
- Audio timeline clips now play during editor playback and stop when playback pauses.
- Added MP4 frame-sequence export, a progress indicator, and audio muxing for audio clips and video-source audio tracks. This export path uses the CPU/SwiftUI renderer and may be slow for long/high-resolution projects.
- Connected real processors for Lens Blur (soft-blur approximation), Threshold, procedural Displacement Map, Luma Fade, VHS, Pixel Sort, RGB Blur, Motion Blur (directional approximation), and Motion Tile.
- Added tests for the expanded effects list; all 234 MotionCore tests pass in Linux Swift.

### Still incomplete / needs device validation

- The app has not been compiled with Xcode or tested on iPadOS 17/iOS 17 in this environment. The PhotosPicker video transfer and MP4 writer/muxer must be checked by the GitHub Actions iOS build and on the target iPad.
- Video preview still decodes one frame at a time from the playhead. It is not a real-time AVPlayer/Metal compositor, so video playback and heavy effect stacks can still lag.
- The preview is capped at 768 px, but there is no user-selectable preview-quality mode, GPU/Metal renderer, effect proxy mode, or full cache/profiling system.
- Export progress is shown, but ETA, cancellation, background export, and robust recovery after export failure are not implemented. If no timeline audio can be inserted, export is video-only.
- Audio playback is a basic AVAudioPlayer implementation, not sample-accurate multi-track mixing; there is no waveform visualizer, gain/volume automation, fades, audio effects, or audio scrubbing preview.
- Effects still apply only to image/video pixel layers. Text and shape colour is editable, but text/shape rasterization for effect stacks is not implemented.
- Lens Blur is not a physically based bokeh lens; Displacement Map is a procedural fallback and cannot reference a separate map layer; Motion Blur is a directional image blur, not shutter-sampled object motion; VHS is a stylised approximation; Motion Tile repeats within the layer bounds.
- No gradient-fill layer, editable custom graph with draggable/addable points, auto-caption transcription workflow, vector pen/path drawing, adjustment layer, clipping masks, luma matte layer workflow, or separate map-source linking was added in this pass.
- Imported image layer names can already be changed with the layer-name field. This does not rename the underlying media asset/file label.
- No full text styling/size/weight/line-spacing controls, keyframe graph handles, marker snapping, multi-select/grouping, relink missing media, project-package import/export, layer lock, preserve-world-transform parenting, precompositions, 3D, tracking/stabilisation, particles, expressions, time remapping, plugin compatibility, or After Effects project import.

### Validation performed

- `swift test --package-path MotionCore`: 234 tests passed.
- Swift syntax parser: all App, MotionCore source, and test Swift files parsed.
- `python scripts/check_repository.py`: passed; 173 effect catalogue names and 78 Swift files checked.
- These checks do not substitute for an iOS SDK compile or real iPad testing.
