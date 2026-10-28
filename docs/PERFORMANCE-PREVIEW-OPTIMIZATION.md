# Preview performance optimisation (Batch 6)

This patch reduces preview work while playback is running:

- The regular preview decode limit is reduced from 768 to 512 pixels on the longest side.
- Playback preview uses a 320-pixel longest side for image/video sources, reducing CPU pixel processing substantially.
- Video frame requests during playback are quantised to 12 frames per second. This avoids asking `AVAssetImageGenerator` for a new unique frame at every display-link tick and limits duplicate in-flight decode work.
- The preview uses the reduced playback path only while `EditorModel.isPlaying` is true. Still-image export continues to use the normal preview path.
- The processed-image cache holds up to 36 entries.

## Known limitation

This is a pragmatic CPU-renderer optimisation, not a full GPU renderer. It trades some playback preview detail and video smoothness for responsiveness. Final video export is not intentionally reduced by this change. Heavy CPU pixel effects may still lag, especially when multiple expensive effects are stacked. The next major performance step is to move common image operations to Core Image/Metal, avoid repeated byte-to-float conversion, and profile on a physical iPad with Instruments.

## Checks

- `python3 scripts/check_repository.py`: passed.
- Swift frontend syntax parse: passed.
- `swift test --package-path MotionCore`: 234 tests passed.
- Not an Xcode/iOS build and not tested on a physical iPad.
