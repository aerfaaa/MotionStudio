# Batch 10 — Performance and editing UI

## Added

- Persistent user-selectable accent colour, with six presets and a custom colour picker in Settings.
- Subtle system material surfaces on the main editor toolbar, transport controls and shared panels. The workspace keeps its existing layout so it remains familiar on iPhone and iPad.
- Audio waveform display for audio timeline layers. Peaks are extracted asynchronously from the project's local audio file and drawn with one Canvas pass, not a large number of SwiftUI subviews.
- Asynchronous AVAssetImageGenerator frame extraction and wider frame-time tolerance to avoid blocking a worker on synchronous copyCGImage calls and to allow nearby frames during preview.
- Core Image fast path for Posterize and CMYK Halftone Dots, in addition to previously supported common effects.

## Improved

- The custom accent is read from UserDefaults and applied to the app tint, timeline playhead and accent-highlighted controls.
- Timeline audio clips now show a waveform under the clip bar. The waveform loads only when its local asset URL is available and is generated away from the UI thread.
- Video frame extraction is scheduled asynchronously through AVFoundation and reuses pooled generators. This improves responsiveness and can reduce exact-seek overhead.

## Not fixed / limitations

- The current video layer preview is still based on extracted frames; it is not yet a continuous AVPlayerItemVideoOutput playback renderer. Do not assume this alone will solve low frame rate during playback.
- The existing export pipeline still uses SwiftUI ImageRenderer per frame. A dedicated composition renderer and AVAssetWriter pixel-buffer pipeline are still needed for a large export-speed improvement.
- Waveforms show audio amplitude, but the app's audio playback is not yet sample-accurately synchronised with video throughout the timeline. The waveform is not a guarantee of real-time audio playback.
- The Core Image CMYK Halftone path is a GPU-backed approximation of the app's existing halftone effect; appearance may differ from the CPU implementation.
- Liquid-glass styling is intentionally subtle and uses standard SwiftUI material. This is not a custom Metal glass shader.
- No Xcode/iOS build or physical-device test was available in this environment.

## Checks performed

- `python3 scripts/check_repository.py` passed.
- Swift frontend syntax parsing for all app source files passed.
- `swift test --package-path MotionCore` passed: 235 tests, 0 failures.
- ZIP archive integrity checked after packaging.
