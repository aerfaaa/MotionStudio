# Graph editor

**Status: foundations only. There is no graph screen yet.**

## What exists

- Every keyframe stores how to travel to the next one: `hold`, `linear` or a cubic Bezier ease `(x1, y1, x2, y2)` (the same convention as CSS `cubic-bezier`).
- `BezierEase.solve(x)` gives the eased progress; `BezierEase.derivative(at:)` gives its slope. The slope is the Speed Graph: 1 means the speed of a straight line, above 1 is faster, below 1 slower, below 0 is moving backwards (overshoot settling).
- `AnimatedProperty.speed(at:)` gives real speed in units per second for numbers and for two-number properties (the length of the velocity).
- `AnimatedProperty.sampledValues(from:to:count:)` samples the Value Graph.
- `segment(at:)` finds the keyframe pair around a time.
- Eight easing presets (`EasingPreset`): linear, hold, ease in, ease out, ease in and out, strong acceleration, soft landing, overshoot. Choosing one writes ordinary editable keyframe easing.
- In the app: select a keyframe in the timeline, choose a preset, and see the curve drawn.

## Tests

`GraphMathTests`: derivative values (computed separately), slope against measured slope, overshoot, speed of linear, hold and eased segments, vector speed, speed area equals total change (links the two graphs), segment lookup, sampling, frame-accurate evaluation at 29.97 fps. `KeyframeEditingTests`: moving, easing changes, copy and paste, delete, undo, save and reload.

## What is missing

| Feature | Status |
|---|---|
| Graph view with value and speed modes | Missing |
| Dragging keyframes in value and time on the graph | Missing (timeline retiming exists) |
| Tangent handles with independent in and out influence | Missing. The model has one ease per segment, so a handle on one side changes that segment only. Separate in and out influence needs a model change. |
| Break and reconnect handles, continuous Bezier | Missing |
| Spatial interpolation separate from temporal | Missing. Position uses one temporal ease for x and y. |
| Multi-curve view, isolate, zoom, pan, fit | Missing |
| Reverse, offset, stretch, compress selections | Missing |
| Bounce, spring, elastic, loop presets | Missing |

## Next step

Draw the Value Graph for one selected property from `sampledValues` and let a dragged handle edit `BezierEase`. Then add the Speed view from `derivative`.
