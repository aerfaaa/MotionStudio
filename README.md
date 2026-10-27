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
- **Effects panel** for image layers: 15 working-in-code effects (Brightness / Contrast, Hue Shift, Saturation, Invert, Gaussian Blur, Sharpen, Vignette, Drop Shadow, Glow, Gradient Map, RGB Split, Pixelate, Posterize, Directional Blur, Wave Warp), stackable, reorderable, switchable on and off, saved with the project and undoable.
- A registry of all 167 required effect names plus Drop Shadow. The other 153 are names only.

## What is not there yet

Effects on shapes or text, the other 153 catalogue effects, graph editor screen, video, audio, text, fonts, masks, mattes, export, time remapping, expressions, 3D. See `docs/FEATURE-STATUS.md` for the full matrix, `docs/MEDIA-AND-EFFECTS.md` for how import and effects work, and `docs/EFFECTS-CATALOG.md`.

## Honest status

The code was written without access to Xcode, a Mac or an iPhone, so **nothing has been compiled or run**. Calculations such as the time system were cross-checked with an independent script, but expect compile errors on the first build. Fix them from the GitHub Actions logs.

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
