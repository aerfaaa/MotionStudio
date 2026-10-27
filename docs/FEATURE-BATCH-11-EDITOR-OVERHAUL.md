# Feature batch 11 — Rendering and editor overhaul

## Implemented in source

- Added a per-frame export counter (`current / total`) alongside percentage progress.
- Added a cached vector-layer rasterization path for solid, shape and text layers with active supported effects. It uses the existing Core Image fast path when possible and MotionCore's CPU `EffectPipeline` otherwise. The cache signature includes layer identity, visual source data and resolved effect parameters.
- Allowed the existing effect commands and Effects panel to add effects to solid, shape and text layers; audio and null layers remain unsupported.
- Added a proportional scale handle at the selected layer's transformed lower-right corner.
- Expanded the alignment overlay with thirds, center axes and a 5% safe frame.
- Reworked the project home screen with a welcome banner, clearer new-composition action, workspace feature tiles, project count and improved recent-project cards.

## Important limitations

- The scale handle edits the layer's scale uniformly; it does not yet provide independent X/Y handles, rotation handles, edge snapping to other layers, or a full After Effects transform gizmo.
- Vector effects are rasterized at up to 2048 px on the longest side for preview. The cache reduces repeat work, but vector-effect rendering is currently synchronous on the first render of a new effect state and can cause a brief preview stall for expensive effects.
- The export frame counter reports progress, but the current export still renders frames through the existing `ImageRenderer` path. This is not yet a persistent background render queue with dependency-aware frame invalidation, nor a guarantee that edits restart a cached preview render from frame zero.
- The UI warns that edits during export may affect later frames. A fully immutable project snapshot and cancellation/restart controls are still future work.
- No Xcode or physical iOS device was available in this environment. Run the iOS GitHub Actions workflow before treating this batch as build-verified.


## Batch 12 additions

- Added an MP4 export settings sheet with a 2–50 Mbps bitrate slider and five quick presets. The chosen target is passed to AVAssetWriter as `AVVideoAverageBitRateKey` and remembered between launches.
- Audio muxing now requests passthrough export so it does not intentionally transcode the video a second time with an unrelated “highest quality” preset; the selected video bitrate should therefore be preserved when passthrough is supported.
- Video export checks task cancellation while waiting for writer capacity and between frames.

Bitrate is a target rather than a guaranteed file size or perceptual-quality score. No device/Xcode build or runtime export test was available in this environment.
- The export sheet estimates video-data size from bitrate × duration and gives a resolution-aware quality hint. The writer reuses one sRGB colour space across frames to avoid repeated per-frame allocation.
- Added a cancel button to the export progress overlay; cancellation is checked between frames and while waiting for writer capacity. The editor restores its original playhead after either success, failure, or cancellation.
- Fixed the error alert binding so dismissing an error changes the actual presentation state instead of using a constant binding.
