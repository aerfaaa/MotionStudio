# Feature Batch 15 — Preview cache, editing feedback and export reliability

## Included

- Reinstated composition third-lines and safe margins, plus high-contrast centre snapping guides and haptic feedback.
- Added a global haptic feedback switch in Settings. Supported controls use a central preference-aware haptic helper.
- Fixed a Photos picker dismissal conflict: the picker is hosted by SwiftUI, so its coordinator no longer dismisses it manually before the parent sheet closes. This avoids a double dismissal that could take down the editor cover.
- Added a bounded, low-resolution composited-frame RAM + disk preview cache (48-frame RAM cap, 36 MiB RAM budget and 180 MiB disk budget). A separate image provider renders ahead while playback runs; cached snapshots are reused, and the timeline ruler displays green segments for frames in the cache. Any project command invalidates snapshots to prevent stale frames.
- Changed motion blur to be temporal/transform-based only. The bitmap pipeline no longer applies a static directional blur; the evaluator's transform samples create the blur trail when keyframed transforms change. Increased transform sample cap from 8 to 16.
- Added a moving-gradient project-browser hero.
- Added an optional automatic Save to Photos setting for still and video exports, with add-only Photos permission text in `project.yml`.

## Verification

- `swift test --package-path MotionCore` passes (237 tests after the motion-blur regression test is added).
- Swift syntax parsing is run over all Swift source files.
- iOS/Xcode build and on-device playback remain unverified in this environment. The cache uses a low-resolution composited snapshot, so it is a RAM-preview optimisation rather than a complete disk-backed After Effects render cache. Export still uses the full-resolution frame exporter and should be measured on a device.
