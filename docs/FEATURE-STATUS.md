# Feature status

Labels: **Working** = implemented and verified by tests or runtime checks. **Partial** = some real behaviour exists. **Missing** = not implemented. **Blocked** = cannot proceed until a documented issue is resolved.

**Important:** no Swift code in this project has ever been compiled or run (the working environment has no Swift, Xcode or Mac). So nothing is labelled Working. Items marked Partial are written, and the "Evidence" column says what was actually checked.

## Baseline audit (this pass)

- The workspace matches the delivered `MotionStudio.zip`: 60 files, about 4,450 lines of Swift before this pass.
- Entry point `App/MotionStudioApp.swift`; core in `MotionCore`; `ResolvedFrame` is the renderer contract, as documented.
- Before this pass: keyframe diamonds in the timeline were display-only markers (the property buttons could add or remove keyframes, but keyframes could not be selected, moved, copied or given easing); scale was uniform only; the theme was dark only; the project list had no thumbnails.
- `FrameRenderer` abstraction: not added (as specified).

## Visual design to preserve

Graphite surfaces with 18 pt rounded panels and thin hairline borders; blue accent for selection; amber reserved for keyframes; the composition preview as the brightest element; sentence-case labels; 44 pt touch targets. The light theme keeps the same structure with lighter surfaces.

## Matrix

| Area | Feature | Status | Evidence / notes |
|---|---|---|---|
| Time | Exact ticks (141,120,000/s), rational frame rates, no drift | Partial | Maths cross-checked with an independent script (all required frame and audio rates exact, 24 h no drift). Swift tests written, never run. |
| Time | Frame-based playback independent of screen refresh | Partial | `PlaybackClock` and tests written. Not run. |
| Animation | Linear, hold, Bezier interpolation | Partial | Tests written; expected values computed separately. |
| Animation | Keyframe add, select, move (drag, snaps to frames), delete, copy, paste | Partial | New this pass. Core commands have tests; the timeline interaction has never run. |
| Animation | Easing presets with curve preview | Partial | Eight presets. |
| Animation | Independent X/Y scale | Partial | Two number fields with a link button. |
| Animation | Spatial (motion path) vs temporal interpolation | Missing | One temporal ease per segment, applied to x and y together. |
| Animation | Bounce, spring, elastic, loop presets | Missing | Need multi-keyframe generation. |
| Graph editor | Speed and value maths (derivative, speed, samples) | Partial | New this pass, with tests whose expected values were computed separately. |
| Graph editor | Graph UI, handle dragging, multi-curve view | Missing | See `GRAPH-EDITOR.md`. |
| Composition | Custom size, aspect presets (9:16, 16:9, 1:1, 4:5, 3:4), frame rate, length | Partial | New project and composition settings screens. |
| Composition | Resizing does not stretch artwork | Partial | Test written. |
| Timeline | Draggable divider, collapse and expand, remembered size | Partial | Portrait and iPad layouts. Not in iPhone landscape. |
| Timeline | Horizontal zoom and scroll | Missing | Fits to width only. |
| Timeline | Markers; snapping to markers and keyframes | Missing | Frame snapping only. |
| Layers | Rectangle, ellipse, solid; rename, duplicate, reorder (command only), hide, delete | Partial | Reorder and trimming have commands and tests but no interface. Lock: missing. |
| Layers | Trimming and timing | Partial | Command only, no interface. |
| Layers | Text, image, video, audio, shape paths | Missing | |
| Layers | Multi-select, grouping, alignment, guides | Missing | |
| Layers | Parenting and null layers | Partial | Evaluated and tested. No interface to create them. |
| Persistence | Folder format, atomic save, schema version, refuses newer files | Partial | Tests written. |
| Persistence | Migrations | Missing | Only a version check exists. |
| Persistence | Autosave (0.7 s after changes, on background) | Partial | Crash recovery beyond atomic writes: missing. |
| Home | Cards with thumbnails, rename, duplicate, delete | Partial | |
| Home | Import and export project packages, relink assets | Missing | |
| Appearance | System, Light, Dark, remembered | Partial | |
| Appearance | Liquid Glass on iOS 26 | Missing | Deliberately deferred: its API cannot be checked without a compiler and could break the build. Materials-based look planned for iOS 17 and 18. |
| Accessibility | Labels on controls, large touch targets | Partial | No audit done. Reduced-motion: nothing animates yet. |
| Media | Photos and Files import, fonts, audio waveforms | Missing | |
| Rendering | CPU preview (SwiftUI Canvas) | Partial | Solid and shape layers, opacity, blend modes. |
| Rendering | Metal renderer | Missing | |
| Export | MP4 export, still export, progress, Photos and Files saving | Missing | See `RENDERING-AND-EXPORT.md`. |
| Effects | Registry of all 167 required names, categories, validation | Partial | Name coverage test written. |
| Effects | Any effect actually rendering | Missing | 0 of 167. |
| Effects | Effect panel, stacking UI, presets, favourites | Missing | Stack data model and evaluator exist; no UI. |
| Time remapping | Speed, reverse, freeze, ramps, blending, optical flow | Missing | Needs the media pipeline first. |
| Compositing | Masks, mattes, keying | Missing | |
| Tracking and stabilisation | | Missing | |
| 2.5D and 3D | | Blocked | Needs a 4x4 transform design first (`Affine2` is 2D). |
| Expressions | | Missing | |
| Precompositions | | Missing | Model holds several compositions; no precomp layer kind. |
| Particles | | Missing | |
| After Effects plugins | | Blocked | Not possible on iOS. See `PLUGIN-COMPATIBILITY.md`. |
| After Effects projects (.aep) | | Missing | Not investigated. |
| Build | GitHub Actions: tests, simulator build, unsigned IPA, screenshots, logs | Partial | Written, never run. |
| Build | iOS 17 minimum; iPhone XS and iPad Pro (2017) | Partial | iOS 17 is set in `project.yml`. Device compatibility is unverified. |
