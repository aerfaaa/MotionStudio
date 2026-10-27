# Feature status

Labels: **Working** = implemented and verified by tests or runtime checks. **Partial** = some real behaviour exists. **Missing** = not implemented. **Blocked** = cannot proceed until a documented issue is resolved.

**Validation note:** MotionCore was compiled and its automated tests were run in a Linux Swift environment. The iOS app itself has not been built with Xcode in this environment, and iPad runtime behaviour has not been verified. Items marked Partial may have passing core tests but still require GitHub Actions/iOS device validation.

## Audit for the media and effects pass

Checked in the source before editing: image layers (`LayerKind.image`) existed in the model but nothing created them, the renderer drew them as plain rectangles, `Asset` had no pixel size, effects were saved and evaluated but nothing processed them and no interface existed. Existing projects (no assets, no effects) must keep opening: asset pixel size is optional, effect lists default to empty. No project format version bump was needed; older files decode as before (tested).

## Baseline audit (earlier pass)

- This status document predates Feature Batch 4; the current project contains additional media, text, null-parenting and effects work. See `FEATURE-BATCH-4.md` for the current implementation and limitations.
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
| Timeline | Horizontal zoom and scroll | Partial | Implemented in the delivered Batch 3 ZIP; needs device verification. |
| Timeline | Markers; snapping to markers and keyframes | Missing | Frame snapping only. |
| Layers | Rectangle, ellipse, solid; rename, duplicate, reorder (command only), hide, delete | Partial | Reorder and trimming have commands and tests but no interface. Lock: missing. |
| Layers | Trimming and timing | Partial | Command only, no interface. |
| Layers | Text, image, video, audio clips | Partial | Text and audio/video clip model types exist. Video frames are generated for the playhead; synchronized audio playback is missing. |
| Layers | Vector pen paths and editable Bézier shapes | Missing | |
| Layers | Multi-select, grouping, alignment, guides | Missing | |
| Layers | Parenting and null layers | Partial | Null creation, parent picker and cycle prevention are implemented; preserve-world-transform parenting is not. |
| Persistence | Folder format, atomic save, schema version, refuses newer files | Partial | Tests written. |
| Persistence | Migrations | Missing | Only a version check exists. |
| Persistence | Autosave (0.7 s after changes, on background) | Partial | Crash recovery beyond atomic writes: missing. |
| Home | Cards with thumbnails, rename, duplicate, delete | Partial | |
| Home | Import and export project packages, relink assets | Missing | |
| Appearance | System, Light, Dark, remembered | Partial | |
| Appearance | Liquid Glass on iOS 26 | Missing | Deliberately deferred: its API cannot be checked without a compiler and could break the build. Materials-based look planned for iOS 17 and 18. |
| Accessibility | Labels on controls, large touch targets | Partial | No audit done. Reduced-motion: nothing animates yet. |
| Media | Image import from Photos and Files, stored in the project, shown as image layers | Partial | Import code, security-scoped access and coordinated file copies are implemented; iPad device test remains outstanding. |
| Media | Video import and playhead-frame preview | Partial | Video files become timeline layers and preview frames are generated at the current composition time. Real-time video playback is not complete. |
| Media | Audio import and extract audio from video | Partial | Audio files can become timeline clips; video audio can be extracted to M4A and added to the timeline. Playback, waveform and mixing are missing. |
| Media | Custom font import and selection for text | Partial | TTF/OTF files are stored and registered for the process; text layers can select registered font names. Device validation remains outstanding. |
| Media | Relink missing media | Missing | Missing files show a placeholder and a message. |
| Rendering | CPU preview (SwiftUI Canvas) | Partial | Solid, shape and image layers, opacity, blend modes. Images are shown from a reduced copy. |
| Rendering | Effects processed off the main thread with caching | Partial | `LayerImageProvider`. Never run, never profiled. |
| Rendering | Metal renderer | Missing | |
| Export | Current-frame PNG/JPEG export and system share sheet | Partial | Uses SwiftUI ImageRenderer; actual iOS runtime testing remains outstanding. |
| Export | MP4 export, progress, ETA, audio-inclusive render | Missing | See `RENDERING-AND-EXPORT.md`. |
| Effects | Registry of all 167 required names (plus Drop Shadow), categories, validation | Partial | Name coverage test written. |
| Effects | Existing 15 processors plus Chroma Key, Box Blur, Zoom Blur, Noise, CMYK Halftone Dots, Roughen Edges and procedural Random Displacement | Partial | MotionCore tests pass. Video effects apply to generated preview frames, not a completed video-export pipeline. See `FEATURE-BATCH-4.md`. |
| Effects | Remaining catalogue effects | Missing | Includes Motion Blur, Lens Blur, Rays and time-dependent Oscillate/Flicker/Jitter. |
| Effects | Effects panel: search, categories, add, list, enable, reorder, remove, reset, settings, colour picker | Partial | Never run. |
| Effects | Undo for add, remove, reorder, enable, settings; saving and order | Partial | Command tests written. |
| Effects | Keyframes on effect settings | Partial | Data and commands support it. No interface. |
| Effects | Presets, favourites, recents, copy and paste of stacks | Missing | |
| Effects | Effects on shape and text layers | Missing | Current pixel effects require rasterized content. |
| Effects | Effects on video layers | Partial | Applied to sampled video frames in preview; no video export pipeline yet. |
| Time remapping | Speed, reverse, freeze, ramps, blending, optical flow | Missing | Needs the media pipeline first. |
| Compositing | Chroma Key | Partial | Pixel processor connected and tested. Editable mask paths, clipping masks and mattes remain missing. |
| Compositing | Clipping masks and editable masks | Missing | |
| Tracking and stabilisation | | Missing | |
| 2.5D and 3D | | Blocked | Needs a 4x4 transform design first (`Affine2` is 2D). |
| Expressions | | Missing | |
| Precompositions | | Missing | Model holds several compositions; no precomp layer kind. |
| Particles | | Missing | |
| After Effects plugins | | Blocked | Not possible on iOS. See `PLUGIN-COMPATIBILITY.md`. |
| After Effects projects (.aep) | | Missing | Not investigated. |
| Build | GitHub Actions: tests, simulator build, unsigned IPA, screenshots, logs | Partial | Workflow exists; this batch was not run through GitHub Actions. |
| Build | iOS 17 minimum; iPhone XS and iPad Pro (2017) | Partial | iOS 17 is set in `project.yml`. Device compatibility is unverified. |
