# Media import and effects

**Status: written, never compiled or run.** Every label below that says Partial means real code exists with tests written, not that it has been seen working.

## How to use it (once the app is installed)

**Import an image**
1. Open or create a project.
2. Tap the picture icon with a plus in the top bar ("Import image").
3. Choose **Photo Library** or **Files**, then pick a picture.
4. A new image layer appears, centred and fitted inside the composition with its proportions kept. Select it and move, scale, rotate or fade it with the normal controls. Cancel the picker and nothing happens.

**Add an effect**
1. Select the image layer.
2. Open the **Effects** tab (next to Timeline and Properties; on iPad it is the side panel's second tab).
3. Tap **Add effect**, search or filter by category, tap an effect.
4. Select the effect in the list to see its settings. The preview updates a moment after each change. The switch turns an effect on or off; the ... menu moves it up or down, resets it or removes it.
5. Effects run from the top of the list to the bottom, so the order changes the result.

Effects work on **image layers**. Other layer types show a message instead.

## Where files go

Each project is a folder: `Name.motionproj/project.json` and `Name.motionproj/media/`. Imported pictures are copied into `media/` (so temporary picker files are never relied on), and the project saves only the relative path such as `media/3F2A9C11-Photo.jpg` plus the picture's pixel size. Duplicating a project copies its media. If a file goes missing the layer shows a grey placeholder with a cross, and the Properties panel says the file is missing. Only `media/<file>` paths are accepted, so a damaged or hostile project file cannot point elsewhere on the device.

Limits: 16,384 pixels on a side and 150 million pixels. Large photos are never decoded in full for the preview; a reduced copy (at most 1,024 pixels on the long side) is used.

## How effects are built

| Piece | Where | What it is |
|---|---|---|
| Definition | `EffectRegistry`, `EffectParameterTable` | name, id, category, settings, ranges, defaults |
| Instance | `EffectInstance` on a layer | id, which effect, on or off, the settings (which can hold keyframes) |
| Values | `EffectValues` | the settings for one frame, validated: missing, damaged or out-of-range numbers become defaults or are clamped |
| Processing | `ImageEffects` | one function per effect, on a `PixelImage` |
| Pipeline | `EffectPipeline` | runs the enabled effects in order, collects problems |
| Commands | `AddEffect`, `RemoveEffect`, `MoveEffect`, `SetEffectEnabled`, `SetEffectParameters`, `ResetEffect` | every change is undoable |
| Preview cache | `LayerImageProvider` (app) | loads a reduced copy, runs the pipeline in the background, caches results, keeps the previous result on screen until the new one is ready |

Why plain Swift instead of Core Image: the processing can be tested with exact pixel values, behaves identically everywhere, and has no hidden filter behaviour that could not be checked without a Mac. The cost is speed: it runs on the CPU. The pipeline works on a reduced copy and off the main thread so the interface stays responsive, but large blurs may take a moment. Settings measured in pixels are written in layer pixels and scaled to the preview copy, so a preview matches the full-size result. A future Metal path, or the video exporter, can call the same `ImageEffects` or replace them behind `EffectPipeline`.

Settings are stored as animatable properties, so keyframing effect settings later needs no format change. There is no interface for keyframing them yet. Editing a setting that already has keyframes creates a keyframe at the playhead.

Unknown or newer effects in a project file are kept (not deleted), shown as "not recognised" and skipped when drawing.

## The 15 effects

Units are layer pixels unless stated. All keep alpha correct. All return the same picture for neutral settings.

| # | Effect | Settings | Notes |
|---|---|---|---|
| 1 | Brightness / Contrast | brightness -1..1, contrast -1..1 | Contrast multiplies distance from grey by 2^(2 x contrast). Clamped. |
| 2 | Hue Shift | degrees -180..180 | Rotates hue in HSV, so brightness and saturation are kept. |
| 3 | Saturation (listed as "Saturation / Vibrance") | saturation 0..3 | 0 is grey (Rec. 709). **Vibrance is not implemented.** |
| 4 | Invert | none | Inverts colour, not alpha. |
| 5 | Gaussian Blur | radius 0..250, quality, edges | Approximated with repeated box blurs. Edges repeat by default (no transparent border). Zero radius returns immediately. |
| 6 | Sharpen | amount 0..5, radius 0.5..20 | Unsharp mask limited to the 3 x 3 neighbourhood range plus 15 percent, which prevents halos. |
| 7 | Vignette | intensity -1..1, radius, softness, centre | Negative intensity lightens. Distance is elliptical, following the picture's shape. |
| 8 | Drop Shadow | colour, opacity, blur, distance, angle, spread | Made from the layer's alpha, so transparent areas cast no shadow. The canvas grows so the shadow is not cut off. Spread is a square expansion. |
| 9 | Glow | threshold, radius, intensity, colour, output | Bright areas (luminance times alpha) are blurred and added as light. The canvas grows. "Glow only" drops the original. |
| 10 | Gradient Map | three colours, midtone position, mix | Maps brightness to a three-stop gradient. Stops are fixed at 0, the midtone position and 1; stops cannot be added. |
| 11 | RGB Split | red offset, blue offset, intensity | Red and blue sampled from shifted positions, edges repeat. |
| 12 | Pixelate | block size 1..200 | Block average. Blocks start at the top-left of the picture. |
| 13 | Posterize | levels 2..32 | Equal-width steps snapped to evenly spaced values. |
| 14 | Directional Blur | angle, distance 0..500 | Up to 48 samples along the line, edges repeat. |
| 15 | Wave Warp | amplitude, waves per 1000 px, phase, direction, wave type | Sine, triangle or square. Output size is unchanged, edges repeat. |

## Known limits and issues

- Image layers only. Effects on shapes, text and video do not exist yet.
- No video, audio or font import. Only images.
- Effects run on the CPU. Heavy settings on large pictures can take noticeable time (the preview shows the previous result meanwhile). Memory growth from shadows and glow is capped at 200 pixels of border on each side.
- Effects are not part of any export, because there is no export.
- The preview uses a reduced copy (at most 1,024 pixels), so very fine detail is approximate.
- Colours are processed as sRGB values, not in linear light.
- Effect keyframes have data support and no interface.
- Nothing here has been compiled, tested or seen on a device.
