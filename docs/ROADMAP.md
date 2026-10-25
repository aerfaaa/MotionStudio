# Roadmap

Each step ends in something you can see or test.

**V1 (this ZIP): foundation.** Done when: MotionCore tests pass in GitHub Actions; the app builds; on your iPhone you can create a project, add shapes, drag them, set position and opacity keyframes, play, undo, close, reopen and find the same project.

**V1.1: tidy-up from the first real run.** Fix compile errors, layout problems and anything the screenshots show.

**V2: Metal preview.** Replace Canvas with an MTKView renderer for the same `ResolvedFrame`. Done when: it matches the Canvas output on the demo project and holds 60 fps with 20 layers.

**V3: media.** Import from Photos and Files into `media/`, image layers, then video layers (AVAssetReader, frame-accurate), audio and waveforms. Done when: a 10-second clip stays in sync at 29.97 and 59.94 fps.

**V4: export.** Offscreen render of every frame into AVAssetWriter, at 24 to 60 fps and above. Done when: the exported file's frame count and duration match the composition exactly.

**V5: first effects.** Blur, glow, colour correction, chromatic aberration, grain, as built-in GPU effects with animatable parameters and stackable per layer. Done when: each effect visibly changes both preview and export.

**V6: compositing.** Masks, track mattes, blend mode picker, adjustment layers, precompositions.

**V7: animation tools.** Graph editor, custom easing, motion paths, layer trimming and time remapping.

**V8: expressions and presets.** Small expression language, effect presets, animation presets.

**V9: extension SDK.** Effect graph format for third-party effects built from built-in operations.
