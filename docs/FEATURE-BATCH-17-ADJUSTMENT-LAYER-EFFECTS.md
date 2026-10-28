# Batch 17 — Adjustment layers, simpler editing, and four effects

## Adjustment layer

- `Add > New layer > Adjustment Layer` creates a non-rendering layer at the top of the stack.
- Enabled effects on the adjustment layer are inherited by visual layers below it while the adjustment layer is visible and within its in/out points.
- Reorder the adjustment layer to change which layers receive the effects. Hiding the adjustment layer disables its effects.
- The Inspector and Effects panel explain the scope and hide transform/keyframe controls that do not make sense for this layer type.

### Rendering limitation

This first implementation applies adjustment effects to each affected layer before the layers are composited. It is not a true full-composition post-processing pass. This is appropriate for many colour treatments, but spatial effects such as blur can look different around overlapping layers. Adjustment-layer opacity is currently used as an on/off gate, not as a continuous mix amount.

## New connected effects

- **Black & White** — luminance-based grayscale with an amount control.
- **Sepia Tone** — warm sepia matrix blended with the original.
- **Solarize** — inverts channels above a threshold, with an amount control.
- **Tint** — blends pixels toward an adjustable RGB colour.

Each effect has parameter definitions, a real CPU processor, and pixel-level tests. The effect catalogue now has 177 names, with 42 connected processors. Connected effects are still marked Partial until their behaviour and performance are validated on iOS.

## Editing simplification

- Adjustment layer gets a clear dedicated Add-menu action and a distinct timeline icon.
- The Inspector explains adjustment scope rather than showing meaningless transform and keyframe controls.
- The Effects panel repeats the scope hint so users understand why layer order matters.

## Validation

- `python3 scripts/check_repository.py`: passed (repository structure/catalogue check, not an iOS compile).
- `swift test --package-path MotionCore`: 253 passed, 0 failed.
- `find App -name '*.swift' -print0 | xargs -0 -n1 swiftc -frontend -parse`: passed.
- Full Xcode build and physical iOS device tests were not available in this environment.
