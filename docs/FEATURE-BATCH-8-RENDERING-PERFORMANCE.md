# Feature Batch 8 — Rendering performance

## Changes

- Added `CoreImageEffectRenderer`, a hardware-accelerated Core Image fast path for effect stacks consisting only of brightness/contrast, hue shift, saturation, invert, Gaussian blur, and sharpen.
- The fast path creates one Core Image filter graph and renders it once, instead of converting each frame into `PixelImage` float arrays and back through `PixelBridge`.
- Unsupported effects and mixed stacks continue through the existing CPU `EffectPipeline`; this keeps the existing processors available rather than silently dropping effects.
- Video export now asks `LayerImageProvider` for source images up to the composition's longest side instead of reusing the reduced 512-pixel preview limit. Playback preview limits remain unchanged.
- Raised the video preview sample target from 12 to 24 frames per second. More importantly, only one still-frame decode per video asset can run at a time; requests made while it decodes collapse to the latest requested frame instead of building a queue of stale decodes. A failed single video-frame decode no longer permanently marks the whole asset missing.
- Export quality is passed per request instead of stored as a shared mutable mode, so ordinary SwiftUI preview redraws cannot accidentally reset an export frame to preview resolution.

## Known limitations

- This is a hybrid renderer, not a full Metal compositor. CPU-only effects and mixed stacks can still be slow.
- `CISharpenLuminance` and `CIGaussianBlur` are GPU-backed equivalents, not pixel-identical replicas of the current custom CPU algorithms. Gaussian blur is cropped back to the source extent.
- Video source frames are still obtained through `AVAssetImageGenerator`, so the 24 fps target is not a guarantee of 24 fps playback. A continuous `AVPlayerItemVideoOutput` preview and sequential frame decoding for export remain future work.
- Video export still builds a SwiftUI `Canvas`/`ImageRenderer` for each frame. A dedicated composition renderer would be the next major architectural improvement.
- An Apple-platform Xcode build and physical-device benchmark are required to verify framework API compatibility and quantify performance. Linux syntax parsing and MotionCore tests do not verify iOS framework compilation.

## Validation performed

- `python3 scripts/check_repository.py`
- `swift test --package-path MotionCore` — 234 tests passed
- Swift frontend syntax parse for the App Swift files
- ZIP archive integrity check
