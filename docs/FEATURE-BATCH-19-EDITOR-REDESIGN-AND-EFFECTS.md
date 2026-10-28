# Feature batch 19 — editor workspace refresh and new effects

## Editor workspace

- Added a compact preview header with playback/frame state, composition dimensions and a one-tap alignment-guide toggle.
- Refined the preview container with a clearer surface boundary and spacing.
- Reworked the main title area to show save state and the selected layer without crowding the undo/redo/export controls.
- Added Quick Looks in the Effects panel: Film, Glitch, Retro Screen and Soft Glow. These add ordinary editable effects rather than baking a preset into the image.

## New connected effects

- **Chromatic Aberration** — separates red and blue channels along a configurable direction.
- **Film Grain** — deterministic, seeded grain with amount, size and colour/monochrome controls.
- **Scanlines** — repeating horizontal display bands with spacing, strength and phase controls.

Each effect has parameter definitions and pixel-level tests. They are marked **Partial**, like the other connected effects, until the full iOS build and device performance are verified.

## Verification

- `python3 scripts/check_repository.py` passes.
- `swift test` in `MotionCore/` passes: 256 tests, 0 failures.
- Swift frontend parse checks pass for the files under `App/`.
- This environment is Linux, so it cannot validate UIKit/SwiftUI type-checking, Xcode project generation or an iOS device build. Run the GitHub Actions iOS workflow before treating the app build as verified.
