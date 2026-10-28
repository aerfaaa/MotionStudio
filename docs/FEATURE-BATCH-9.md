# Feature Batch 9 — Motion Blur, Custom Graphs, and Playback Cache

## Changes

- Motion Blur now samples animated world transforms around the current composition time and draws temporal trails for text, shapes, images, and video layers. The `shutterAngle` and `samples` parameters control the sampling window/count.
- Keyframe inspector includes a custom cubic-Bezier graph editor with X/Y controls for both handles and overshoot-capable Y ranges. Values are stored as the existing `.bezier(BezierEase)` interpolation, so the project format remains compatible.
- Video preview keeps a bounded LRU cache of decoded source frames instead of deleting all previous video frames on every playhead update. AVAssetImageGenerator is allowed one-frame timing tolerance to reduce expensive exact seeks.

## Limitations

- Temporal motion blur is a transform-trail approximation, not true subframe alpha integration. It draws the same layer source at nearby animated transforms. For footage whose pixels move internally, use the spatial motion-blur effect.
- Video frames are still requested through AVAssetImageGenerator. A production-grade playback pipeline should use AVPlayerItemVideoOutput / AVPlayer or an AVAssetReader pipeline; that larger change requires device profiling and careful source-time/trim handling.
- The preview still uses SwiftUI Canvas. This batch does not claim guaranteed real-time playback on every iPad.
- Xcode/iPad device build is not available in this environment. Swift parsing and MotionCore tests are the available checks.

## Extra performance work

- Video decoding now reuses a bounded pool of `AVAssetImageGenerator` instances keyed by media URL and decode size, rather than constructing a new generator for each frame request.
- Core Image fast path now includes box blur, directional blur and lens/bokeh blur, in addition to the colour and basic blur effects already supported.
- Custom graph slider edits coalesce into a single undo history entry per keyframe property.
