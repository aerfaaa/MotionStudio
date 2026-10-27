# Roadmap

Status labels as in `FEATURE-STATUS.md`. Nothing is Working until it has been built and tested.

| Phase | Content | Status |
|---|---|---|
| V1 foundation | Core, timeline, keyframes, undo, saving, preview | Partial. Written, not built. |
| A. Editor reliability | Timeline resize and collapse, keyframe workflow, X/Y scale, custom sizes, composition settings | Partial. Done this pass: keyframe selecting, moving, copy and paste, easing, scale X/Y, resizable timeline, composition settings. Missing: timeline zoom and scroll, markers, layer trimming interface, migrations, crash recovery. |
| B. Project and interface | Home screen, appearance | Partial. Done: thumbnails, rename, duplicate, System/Light/Dark. Missing: package import and export, Liquid Glass. |
| C. Media and typography | Image import (done in code), video, audio, fonts, text | Images Partial (written, not run). Rest Missing. |
| D. Rendering and export | Metal renderer, MP4 export | Missing |
| E. Effects | Registry, 15 effects with processing, effects panel, presets | Registry and 15 effects Partial (never run). Presets, other 153 effects, non-image layers Missing. |
| F. Advanced animation | Graph editor UI, motion paths, precomps, expressions, time remapping | Maths Partial. Rest Missing. |
| G. Compositing | Masks, mattes, keying, tracking, 3D | Missing. 3D is blocked on a matrix design. |

## Next milestone

1. Run **Core tests** and **iOS build**. Send the first `error:` lines from the logs. Expect compile errors: this release added about 3,000 lines that were never compiled.
2. Use the app: import a picture, add each of the 15 effects, move sliders, save, close, reopen. Report what looks wrong (screenshots help).
3. Then, in order: effects on shape and solid layers (needs rasterising them), effect keyframes in the timeline, effect presets, then the Metal renderer and export.
