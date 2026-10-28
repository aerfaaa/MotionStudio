# Plugins and interoperability

## After Effects plugins: no direct binary compatibility

Desktop After Effects plugins use Adobe's host SDK and are built for the desktop host/platform. An iOS SwiftUI app cannot load Windows `.aex` or macOS `.plugin` binaries as if they were native MotionStudio effects. MotionStudio will not ship a plugin installer that implies otherwise.

## Practical workaround: render the result in After Effects

Use the plugin on a desktop, render the result, then import the rendered media as a video layer through **Add > Files**. See [`AE-PLUGIN-WORKAROUND.md`](AE-PLUGIN-WORKAROUND.md) for the tested conversion prototype and transparent-overlay caveats.

This is a **baked render**, not true plugin support: the plugin's settings, keyframes, expressions, and editable effect stack do not transfer. H.264 MP4 is the safest first test for opaque footage. ProRes 4444 MOV is a possible alpha-preserving interchange file, but MotionStudio's current iOS frame extraction path has not been verified to preserve its alpha channel.

## After Effects projects (.aep)

The format is proprietary. No import exists, and no compatibility is claimed.

## Future portable alternatives

1. **Effect presets**: versioned data files containing settings for MotionStudio's own built-in effects.
2. **Declarative user effects**: a validated graph of built-in operations, stored as data rather than executable code.
3. **Independent implementations**: recreate a visual effect using documented algorithms or licensed/open-source code, then test it in MotionStudio.
4. **LUT interchange**: useful for some colour looks only; it cannot represent arbitrary plugins.

Anything that downloads and executes native or GPU code at runtime should be treated as unavailable until both technical feasibility and platform rules have been checked.
