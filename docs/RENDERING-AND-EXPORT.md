# Rendering and export

## Current pipeline

```
Project -> Evaluator.resolve(composition, frame:) -> ResolvedFrame -> CanvasRenderer (SwiftUI Canvas)
```

`ResolvedFrame` holds, for one frame: size, background and every visible layer in drawing order with its final transform, opacity, blend mode and resolved effect settings. The preview draws it with SwiftUI Canvas on the CPU.

## What is supported

Solid, rectangle, ellipse, image, sampled video, text and audio-layer models; opacity; the four blend modes (normal, add, multiply, screen); 2D transforms with parents; and 42 connected pixel processors across the supported rasterized preview path. Processor completeness varies; connected effects are marked Partial.

### Image layers and effects

```
ResolvedLayer (kind .image, effects with this frame's values)
  -> LayerImageProvider: reduced copy from the project's media folder (ImageIO)
  -> EffectPipeline (background task, MotionCore ImageEffects on a PixelImage)
  -> CGImage -> drawn by CanvasRenderer at the layer's transform
```
The pipeline code is in MotionCore and does not use the screen, so a video exporter can run the same processing on each frame. Results are cached by (picture, size, effect settings). While new settings are processed the previous result stays visible.

## What is not

A Metal renderer, full real-time video playback, synchronized timeline audio playback, masks/mattes, time remapping and production-verified export are not complete. Still-image export and sequential MP4 export code exist, including progress and audio muxing, but require iOS build and device validation.

## Plan

1. **Metal renderer** reading `ResolvedFrame`; the preview view changes to an `MTKView`, nothing else does.
2. **Media**: `AVAssetReader` decoding into textures; images through ImageIO.
3. **Effects**: each effect chosen as Core Image or Metal and written behind the same contract; time-based effects use only the composition time, never the wall clock, so frame-by-frame rendering is deterministic.
4. **Export**: loop `Evaluator.resolve(frame:)` over every frame into an offscreen renderer and `AVAssetWriter` (H.264 or HEVC in MP4), with progress, cancellation, errors and saving to Photos or Files. Preview and export share the evaluator and renderer, so they cannot calculate differently.
5. **Verification**: generate a short clip, then read it back and check dimensions, frame count, duration and timestamps. Automated and on-device export validation remains outstanding.

## Honest limits

Heavy effects, optical flow and particles will need quality presets on older devices (iPhone XS, iPad Pro 2017). Nothing has been profiled on any device.
