# Architecture

## The idea in one picture

```
 touch / UI (App/UI)  ->  EditorModel  ->  Document (undo)  ->  Project (saved data)
                              |                                    |
                              |                                    v
                              +--------------------------->  Evaluator  ->  ResolvedFrame  ->  Renderer
                                                        (keyframes become numbers)     (draws pixels)
```

Four layers, each ignorant of the ones above it:

1. **Project model** (`MotionCore/Model`): plain data. Projects, compositions, layers, animated properties,
   keyframes, effect slots, asset list. Everything is a Swift value type, so a copy is a perfect snapshot.
2. **Editing** (`MotionCore/Editing`): every change is a `Command`. `Document` runs commands and keeps the
   undo and redo history.
3. **Evaluation** (`MotionCore/Evaluation`): `Evaluator.resolve(composition, frame:)` turns the project and a frame
   number into a `ResolvedFrame`: final position, rotation, opacity and effect settings for every visible layer,
   in drawing order. It is pure maths with no screen, files or threads.
4. **Rendering** (`App/Rendering`): draws a `ResolvedFrame`. V1 uses SwiftUI Canvas. A Metal renderer and the video
   exporter will read the same `ResolvedFrame`.

`MotionCore` imports only Foundation, so its tests run on macOS and Linux and it can never accidentally depend on a screen.

## Time

- `Time` is a whole number of **ticks**, 141,120,000 per second.
- `FrameRate` is an exact fraction (29.97 fps is 30000/1001).
- A frame's start time is calculated from its frame number: `time(ofFrame:)` = round(frame x 141,120,000 x denominator / numerator),
  using 128-bit arithmetic. Nothing ever adds up frame durations, so nothing drifts.
- 24, 25, 30, 48, 50, 60, 72, 90, 100, 120, 144, 240 fps, 23.976, 29.97, 59.94 and 119.88 fps, and audio at
  8, 11.025, 16, 22.05, 32, 44.1, 48, 88.2, 96, 176.4 and 192 kHz, are all whole numbers of ticks.
  The unit tests check this, and so did an independent script.
- Any other rate still works: its frame times are rounded once per frame, with an error of at most half a tick.
- The composition frame rate is unrelated to the display refresh rate. During playback `PlaybackClock` works out the frame
  from the real time elapsed, so a 24 fps composition runs at the right speed on a 120 Hz screen.
- Compositions are limited to 24 hours so the maths cannot overflow.

## Composition size vs screen size

The project stores pixels (1920 x 1080). `Viewport` is the only place that converts between composition pixels and screen
points, fitting the composition into whatever space the view has. Touches are converted into composition pixels
before they reach the model. The model never sees a screen measurement.

## Undo and redo

`Document.perform(command)` applies the command to a copy, throws away the edit if it fails or changes nothing, and
otherwise pushes the previous whole project onto the undo stack. Commands with the same `coalescingKey` in a row (a drag, a
slider) merge into one step until `endGroup()`. The limit is 200 steps.

Trade-off: whole-project snapshots are simple and reliable but use more memory than storing small inverse patches.
Projects hold settings and keyframes, not media, so this is cheap for a long time. The API hides the choice, so it can change.

## Saving

A project is a folder: `project.json` plus `media/`. JSON uses sorted keys and is written atomically. Files carry a
`schemaVersion`. A file from a newer app is refused with a clear message; fields added later are read with defaults.
Saves happen 0.7 seconds after the last change, when the app leaves the foreground, and when the editor closes.

## Animation

`AnimatedProperty<Value>` is a fixed value plus a sorted list of keyframes. Each keyframe stores how to travel to the next
one (`hold`, `linear` or a cubic Bezier ease). Editing a property that already has keyframes creates a keyframe at the
current time (auto-keyframing); otherwise it changes the fixed value.

## Extension points

| To add... | Where | What else changes |
|---|---|---|
| A new layer kind (video, text, audio, precomp) | `LayerKind`, then `Evaluator` and the renderer | `schemaVersion` bump |
| An effect | An `EffectInstance` on a layer already exists. Add a built-in effect ID, parameter list and a GPU or CPU implementation in the renderer | Nothing in the model |
| Metal renderer | New renderer that consumes `ResolvedFrame` | Preview view uses an MTKView instead of Canvas |
| Video export | Loop `Evaluator.resolve(frame:)` over all frames into an offscreen renderer and AVAssetWriter | Needs an offscreen renderer |
| Media import | `Asset` list and `media/` folder already exist | Importer UI, decoding |
| Expressions | A formula slot on `AnimatedProperty` evaluated inside `Evaluator` | Dependency ordering between properties |
| Plugins | See `docs/LONG-TERM-REVIEW.md` | Not possible as downloaded native code on iOS |

## Interface

Three layouts from one set of views (`EditorScreen`): stacked (narrow), side by side (iPhone landscape) and three-region (iPad).
Content respects safe areas. Only the background extends behind them.

## Known limits of V1

- The preview renderer is CPU/vector drawing, fine for a few layers, not for heavy compositing.
- Preview zoom and pan exist in `Viewport` but have no gestures yet.
- No trimming or moving of layers in time, no horizontal timeline zoom.
- Scale is uniform in the interface (the model stores x and y).
- Dragging a layer that has a parent would move it in the parent's space. The interface cannot create parents yet.
- Nothing has been compiled or run on a device.
