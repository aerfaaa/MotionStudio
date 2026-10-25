# Motion Studio (working title)

A native iPhone and iPad motion graphics and compositing editor, aiming to bring the ideas of
desktop tools such as After Effects to a touchscreen: layers, keyframes, compositions, effects.
Free and open source (MIT).

This is **version 1**, a deliberately small foundation. It is real, but it is early.

## What works in V1 (by design, not yet tested on a device: see below)

- Projects saved as folders (`Name.motionproj`) and reopened later. Visible in the Files app.
- A composition with a fixed pixel size and frame rate (24, 25, 30, 50, 60, 120 fps and the
  fractional 23.976, 29.97 and 59.94), independent of the screen it is edited on.
- Rectangle, ellipse and solid layers. Tap to select, drag to move.
- Timeline with a draggable ruler, one row per layer and keyframe markers.
- Position, scale, rotation and opacity, each with keyframes (linear interpolation).
- Play, pause, step frame by frame, loop. Playback speed follows the clock, not the screen refresh rate.
- Undo and redo for every edit. Drags count as one step.
- Layouts for iPhone portrait, iPhone landscape and iPad.

## What is not in V1

Video, audio, images, text, effects, masks, mattes, blend mode controls, graph editor, expressions,
Metal rendering and export. The code is organised so these can be added without rewriting the app
(see `docs/ARCHITECTURE.md` and `docs/LONG-TERM-REVIEW.md`).

## Honest status

The code was written without access to Xcode, a Mac or an iPhone, so **it has never been compiled or run**.
The time maths and test numbers were checked with an independent script, but expect a few compile
errors on the first build. That is normal; fix them from the GitHub Actions log.

## Folders

| Folder | What it is |
|---|---|
| `MotionCore/` | The editor's brain: time, animation, layers, undo, saving. No screens. Has the unit tests. |
| `App/` | The SwiftUI iPhone/iPad app. |
| `project.yml` | Recipe that generates the Xcode project on the build machine. |
| `.github/workflows/` | Manual-only build and test jobs for GitHub Actions. |
| `docs/` | Architecture, decisions, review, roadmap, build and install guide. |

## Start here

Read `docs/BUILD-AND-INSTALL.md`.
