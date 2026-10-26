# Rendering and export

## Current pipeline

```
Project -> Evaluator.resolve(composition, frame:) -> ResolvedFrame -> CanvasRenderer (SwiftUI Canvas)
```

`ResolvedFrame` holds, for one frame: size, background and every visible layer in drawing order with its final transform, opacity, blend mode and resolved effect settings. The preview draws it with SwiftUI Canvas on the CPU.

## What is supported

Solid, rectangle and ellipse layers; opacity; the four blend modes (normal, add, multiply, screen); 2D transforms with parents.

## What is not

Effects (settings are evaluated but nothing is drawn), images, video, audio, text, masks, mattes, Metal, export of any kind. **There is no export.** No MP4, no still frame, no share sheet.

## Plan

1. **Metal renderer** reading `ResolvedFrame`; the preview view changes to an `MTKView`, nothing else does.
2. **Media**: `AVAssetReader` decoding into textures; images through ImageIO.
3. **Effects**: each effect chosen as Core Image or Metal and written behind the same contract; time-based effects use only the composition time, never the wall clock, so frame-by-frame rendering is deterministic.
4. **Export**: loop `Evaluator.resolve(frame:)` over every frame into an offscreen renderer and `AVAssetWriter` (H.264 or HEVC in MP4), with progress, cancellation, errors and saving to Photos or Files. Preview and export share the evaluator and renderer, so they cannot calculate differently.
5. **Verification**: generate a short clip, then read it back and check dimensions, frame count, duration and timestamps. This needs a Mac runner and is not done.

## Honest limits

Heavy effects, optical flow and particles will need quality presets on older devices (iPhone XS, iPad Pro 2017). Nothing has been profiled on any device.
