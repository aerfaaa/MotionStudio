# Review against the long-term goal

Goal: an advanced After Effects-inspired editor for iPhone and iPad. This lists what could have blocked it, and what was done.

| Risk | Status in V1 | Cost to fix later |
|---|---|---|
| **Time drift / frame accuracy** | Solved. Ticks plus frame-number maths. Tested. | None |
| **Frame rate tied to screen refresh** | Solved. `PlaybackClock` uses real elapsed time. Display link asks for up to 120 Hz. | None |
| **Composition size tied to device** | Solved. `Viewport` is the only bridge. | None |
| **Renderer welded to the UI** | Mostly solved. Renderers consume `ResolvedFrame`. Presentation differs (Canvas now, MTKView later). | Medium: new preview view, same contract |
| **Effects have nowhere to live** | Reserved. `EffectInstance` with animatable parameters is saved, evaluated and tested. No effects ship, and none are drawn. | Low |
| **Layer kinds closed** | `LayerKind` enum needs new cases plus a `schemaVersion` bump for older apps. | Low |
| **Nested compositions** | The model holds a list of compositions and commands carry a composition ID. There is no precomp layer kind yet. | Medium |
| **Parenting** | Evaluated, loop-safe and tested. No interface. | Low |
| **Blend modes** | Stored, drawn by the Canvas renderer, tested in the model. No picker. | Low |
| **Masks, track mattes** | Not in the model. Would be new optional fields (decoded with defaults). | Medium |
| **3D layers** | **Not supported.** Transforms are 2D (`Affine2`). 3D needs 4x4 matrices and a camera. | High, but contained in `Affine2`, `Evaluator` and the renderers |
| **Expressions** | No slot yet. The evaluator is pure and time-based, which suits expressions, but cross-property references need an evaluation order. | Medium |
| **Motion blur** | The evaluator accepts any time, so sub-frame sampling works. Renderer must do the blending. | Medium |
| **Undo memory** | Whole-project snapshots. Fine for now. | Low (hidden behind `Document`) |
| **Large projects** | Evaluator and renderer are not cached. Fine for a few layers. | Medium (frame cache in Metal phase) |
| **Threading** | Everything is a value type, so background rendering is safe. `EditorModel` is main-actor only. | Low |
| **Colour management** | Colours are sRGB doubles. A Metal pipeline would work in linear 16-bit float and convert at the edges. | Medium |
| **Timeline scalability** | Fits whole composition to width. No zoom or virtualisation. | Medium |
| **Plugins** | See below. | n/a |

## After Effects plugin compatibility

Not possible, and V1 does not pretend otherwise. After Effects plugins are native desktop binaries built for Adobe's SDK on macOS and Windows.
They cannot run on iOS. iOS also restricts downloading and running new native code in apps (App Store guideline 2.5.2; I have not re-checked the current wording).

What the architecture supports instead, in order of risk:
1. Presets and animation presets: pure data.
2. User-built effects made from built-in building blocks: data again (a graph of built-in operations).
3. A small sandboxed expression language: interpreted, no new native code.
4. Open-source effects compiled into the app through pull requests.

Anything that downloads and runs native or GPU code at runtime is high risk for App Store distribution and should be treated as unavailable until proven allowed.
