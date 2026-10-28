# Roadmap

Status labels as in `FEATURE-STATUS.md`. Nothing is Working until it has been built and tested.

| Phase | Content | Status |
|---|---|---|
| V1 foundation | Core, timeline, keyframes, undo, saving, preview | Partial. Written, not built. |
| A. Editor reliability | Timeline resize and collapse, keyframe workflow, X/Y scale, custom sizes, composition settings | Partial. Done this pass: keyframe selecting, moving, copy and paste, easing, scale X/Y, resizable timeline, composition settings. Missing: timeline zoom and scroll, markers, layer trimming interface, migrations, crash recovery. |
| B. Project and interface | Home screen, appearance | Partial. Done: thumbnails, rename, duplicate, System/Light/Dark. Missing: package import and export, Liquid Glass. |
| C. Media and typography | Image import (done in code), video, audio, fonts, text | Images Partial (written, not run). Rest Missing. |
| D. Rendering and export | Metal renderer, MP4 export | Partial. MP4 and still export code exists; Metal and on-device output verification remain missing. |
| E. Effects | Registry, 42 connected pixel processors, effects panel, presets | Registry and 42 processors Partial (core tests pass, iOS runtime not verified). Presets and 135 catalogue processors remain Missing. |
| F. Advanced animation | Graph editor UI, motion paths, precomps, expressions, time remapping | Maths Partial. Rest Missing. |
| G. Compositing | Masks, mattes, keying, tracking, 3D | Missing. 3D is blocked on a matrix design. |

## Next milestone

1. Run **Core tests** and **iOS build**. Send the first `error:` lines from the logs. Expect compile errors: this release added about 3,000 lines that were never compiled.
2. Run the iOS build, then test image/video import, clip snapping, layer reordering, effect parameters, still export and MP4 export on a device. Report any failures with logs/screenshots.
3. Then, in order: effects on shape and solid layers (needs rasterising them), effect keyframes in the timeline, effect presets, then the Metal renderer and export.


## Newly completed in the current source batch
- Adjustment-layer workflow (per-layer effect inheritance; see limitation in FEATURE-STATUS.md).
- Four additional connected colour/stylization processors: Black & White, Sepia Tone, Solarize, Tint.
- Simplified inspector for adjustment layers and clearer in-app scope guidance.
