# Motion Studio (working title)

A native iPhone and iPad motion graphics and compositing editor, aiming to bring the ideas of
desktop tools such as After Effects to a touchscreen: layers, keyframes, compositions, effects.
Free and open source (MIT).

This is **version 1**, a deliberately small foundation. It is real, but it is early.

## What exists (written, never compiled)

- Projects saved as folders (`Name.motionproj`) and reopened. Home screen with preview cards, rename, duplicate and delete.
- New projects with size presets (16:9, 9:16, 1:1, 4:5, 3:4, HD, 4K) or a custom size, and frame rates 23.976 to 120 fps. Size, frame rate and length can be changed later without stretching artwork.
- Rectangle, ellipse and solid layers. Tap to select, drag to move.
- Position, independent X and Y scale, rotation and opacity, each with keyframes.
- Timeline: draggable ruler, selected layer opens into property lanes; select, drag (snaps to frames), copy, paste and delete keyframes; easing presets with a curve preview.
- A timeline you can resize and collapse (portrait and iPad).
- Play, pause, step, loop; playback follows the clock, not the screen refresh rate.
- Undo and redo for every edit; drags are one step.
- System, Light and Dark appearance.
- **Import images** from the Photos library or the Files app. Each is copied into the project and becomes a real image layer you can move, scale, rotate and fade.
- **Effects panel** for visual layers: 45 connected pixel processors, stackable, reorderable, switchable on and off, saved with the project and undoable. New Chromatic Aberration, Film Grain and Scanlines effects join the existing colour, blur, glow, distortion and retro treatments. Quick Looks add editable Film, Glitch, Retro Screen and Soft Glow stacks.
- A registry of 180 effect names. 45 have connected pixel processors and are marked Partial; 135 still have no processor. The new effects include Chromatic Aberration, Film Grain and Scanlines.

## What is not there yet

A graph-editor screen, effect-parameter keyframe controls, masks and mattes, expressions, full parity with the 180-name effect catalogue, and validation of the full app on a real iPhone/iPad. The app's visual effects are connected to supported visual layers, but each processor is still labelled Partial until its full behaviour and on-device performance are verified. See `docs/FEATURE-STATUS.md`, `docs/MEDIA-AND-EFFECTS.md` and `docs/EFFECTS-CATALOG.md`.

## Honest status

The project has now passed the 256-test `MotionCore` suite on Linux and the repository's static checks. The SwiftUI/iOS app itself still needs an Xcode build and a real-device check; Linux tests do not prove the iOS UI compiles or that rendering performance is acceptable.

## Folders

| Folder | What it is |
|---|---|
| `MotionCore/` | The editor's brain: time, animation, layers, undo, saving. No screens. Has the unit tests. |
| `App/` | The SwiftUI iPhone/iPad app. |
| `project.yml` | Recipe that generates the Xcode project on the build machine. |
| `.github/workflows/` | Manual-only build and test jobs for GitHub Actions. |
| `docs/` | Architecture, decisions, feature status, effects catalogue, graph editor, rendering, plugins, roadmap, build and install guide. |
| `scripts/` | `check_repository.py`: checks that need no compiler. |

## Start here

Read `docs/BUILD-AND-INSTALL.md`.

## Recent rendering work

See [`docs/FEATURE-BATCH-8-RENDERING-PERFORMANCE.md`](docs/FEATURE-BATCH-8-RENDERING-PERFORMANCE.md) for the hybrid Core Image fast path and full-resolution export-source changes.


## Real-time effects and preview cache

The current VHS effect has a Metal compute fast path plus a CPU fallback, and processed preview frames are cached in bounded memory. See [`docs/REALTIME-VHS-AND-PREVIEW-CACHE.md`](docs/REALTIME-VHS-AND-PREVIEW-CACHE.md) for current behavior and limitations. A full sequential pre-render queue and on-device performance validation remain future work.

## Effects library refresh
The effect browser now uses a searchable card layout with an icon, short description, category and honest availability badge for every registered effect. Effects without connected processing remain visible as **Coming soon** and cannot be added. See `docs/FEATURE-BATCH-20-EFFECTS-LIBRARY-REDESIGN.md`.
