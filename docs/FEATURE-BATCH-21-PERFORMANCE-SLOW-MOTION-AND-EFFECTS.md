# Feature batch 21 — responsiveness, slow motion and effect additions

## Responsiveness changes
- The preview no longer synchronously decodes an on-disk JPEG snapshot while playback is running. Playback uses a RAM cache hit or the live preview instead of blocking the main thread on disk I/O.
- Reduced the image-layer preview cap from 512 to 448 pixels and playback previews from 320 to 288 pixels. These are preview-only limits; export resolution is unchanged.
- Capped display-link callbacks at 60 Hz. Composition timing still follows elapsed time and the project's frame rate.

## Slow motion
- The Effects panel now provides a video-speed slider when **Optical Flow Slow Motion** is selected on a video layer, instead of only showing “This effect has no settings.”
- The frame provider now respects the effect's enabled state before requesting optical-flow interpolation.
- Optical-flow synthesis remains an export-time path. The interactive preview intentionally uses ordinary asynchronous frame decoding for responsiveness; full optical-flow preview is not claimed.

## New connected effects
- **Color Tune**: hue rotation, saturation and brightness in one editable effect.
- **Glow Scan**: scanline bands plus a configurable highlight glow.
- Added pixel-level tests for both effects and exposed their parameters in the effects library.

## UI additions
- Added Dreamy, Neon and Night Vision Quick Looks. They are stacks of editable effects rather than flattened filters.

## Verification and limitations
- `swift test --package-path MotionCore`: 259 tests passed.
- `swiftc -frontend -parse` passed for all app Swift files.
- `scripts/check_repository.py` passed its repository checks.
- A full Xcode/iOS type-check, simulator build and physical-device test are not available in this Linux environment. The new IPA must still be built by the macOS iOS workflow and tested on the iPad Pro 2017.
