# Roadmap

Status labels as in `FEATURE-STATUS.md`. Nothing is Working until it has been built and tested.

| Phase | Content | Status |
|---|---|---|
| V1 foundation | Core, timeline, keyframes, undo, saving, preview | Partial. Written, not built. |
| A. Editor reliability | Timeline resize and collapse, keyframe workflow, X/Y scale, custom sizes, composition settings | Partial. Done this pass: keyframe selecting, moving, copy and paste, easing, scale X/Y, resizable timeline, composition settings. Missing: timeline zoom and scroll, markers, layer trimming interface, migrations, crash recovery. |
| B. Project and interface | Home screen, appearance | Partial. Done: thumbnails, rename, duplicate, System/Light/Dark. Missing: package import and export, Liquid Glass. |
| C. Media and typography | Import, fonts, text | Missing |
| D. Rendering and export | Metal renderer, MP4 export | Missing |
| E. Effects | Registry (done), rendering (0 of 167), effect panel, presets | Registry Partial. Rest Missing. |
| F. Advanced animation | Graph editor UI, motion paths, precomps, expressions, time remapping | Maths Partial. Rest Missing. |
| G. Compositing | Masks, mattes, keying, tracking, 3D | Missing. 3D is blocked on a matrix design. |

## Next milestone

1. Run the workflows, fix whatever the compiler reports, and read the simulator screenshots.
2. Then, in order: the first rendered effects through the Canvas renderer (Gaussian Blur, Brightness / Contrast, Hue Shift, Invert map onto Canvas filters), the effect panel, then the Metal renderer and export.
