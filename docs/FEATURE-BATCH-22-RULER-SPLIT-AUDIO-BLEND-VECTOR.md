# Feature Batch 22 — Ruler controls, clip tools, audio gain, blending and vector drawing

## UI controls
- Replaced conventional slider controls in effect parameters and transform properties with a tactile tick-ruler control.
- Numeric values remain editable beside the ruler; dragging adjusts the value and clamps it to the parameter range.

## Timeline and clip tools
- Added Split at Playhead to the selected-layer inspector. It creates a right-hand segment and preserves the left segment's timing.
- Split segments preserve media source offsets so a split video/audio clip continues from the correct source position.
- Added a separate timeline label colour with Reset. It changes only the timeline clip bar, not the visible layer fill.
- Added Normal, Add, Multiply and Screen blend modes to the inspector.

## Audio
- Added a per-audio-layer 0–100% gain control.
- Playback applies the gain to the AVAudioPlayer; the video export audio-mix pass applies the same gain.

## Vector drawing
- Added a Vector Drawing action under Add. Draw a freehand stroke, then add it as an editable vector-path layer.
- Vector paths are persisted in project files and can be transformed, recoloured, blended, split, and processed by the existing vector effect renderer.

## Effects and motion blur
- Added functional Bloom, Duotone and Glitch Lines effects, including parameters, browser entries, metadata and pixel-level tests.
- Motion blur remains transform/temporal based rather than blurring a still bitmap. Its quality option now caps the sample count (Draft 4, Standard 8, High 16), and its angle biases an existing trail without making static layers blurry.

## Validation
- `swift test --package-path MotionCore`: 262 tests passed.
- All App Swift files passed syntax parsing.
- Repository checks passed. A full Xcode/iOS build and physical-device test were not available in this environment.
