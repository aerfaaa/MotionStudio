# Feature Batch 16 — Clip snapping and layer ordering

## Added

- Timeline clip bodies can be dragged horizontally without changing their duration.
- Clip movement stays frame-aligned and can snap the clip's start or end to another clip edge, the composition start/end, or the nearest frame.
- A haptic fires when the active snap target changes. It respects the global Haptic feedback setting.
- Clip-edge snapping is enabled by default, can be toggled directly from the timeline header, and is also available in Settings.
- Layer rows expose a drag handle. Drag a handle onto another layer row to change stack order.
- Layer row context menus provide Move to Top, Move Up, Move Down and Move to Bottom as a discoverable fallback.
- Reordering uses the existing `ReorderLayer` command, so it participates in undo/redo and project saving.
- Added unit tests for snapping to adjacent clip edges, disabling edge snapping while retaining frame alignment, and composition-end clamping.
- Connected seven additional pixel effects: Color Temperature, Colorize, Exposure / Gamma, Find Edges, Flip Layer, Mirror and Mosaic. Each has settings and deterministic pixel-level tests.
- The connected processor count is now 38 of the 177 catalogue entries. These are labelled **Partial**, not production-complete; the rest remain unavailable in the effect browser rather than pretending to work.

## Validation performed in this environment

- `swift test --package-path MotionCore`: 247 tests passed.
- `python3 scripts/check_repository.py`: passed.
- Swift syntax parsing for every app Swift file: passed.

## Not verified here

This environment does not have Xcode or an iOS simulator/device. These checks do not prove the SwiftUI app target type-checks, nor that drag/drop, haptic behaviour, Photos import, export performance, or rendering are correct on an iPhone/iPad. Run the repository's **iOS build** GitHub Actions workflow to catch iOS compiler errors before installing the unsigned IPA.

## Remaining larger gaps

- A desktop `.aex` After Effects plugin is not loaded directly by the iOS app; it needs a native port or a separate compatible render bridge.
- The effect catalogue contains 177 names, but only a subset have connected image processors and those are currently classified as partial rather than fully production-verified. Full effect parity is not complete.
- Export is full-resolution, sequential frame rendering. It has not been benchmarked on hardware, and complex projects can still be slow.
- The preview frame cache is bounded and low-resolution by design; it is not a guarantee of real-time playback for every composition.
- Motion blur, video playback, media importing, and Photos saving still require on-device validation.
