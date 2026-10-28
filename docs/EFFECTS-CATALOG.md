# Effects catalogue

Every effect name required by the product specification is registered in `MotionCore` (`EffectRegistry`) with its exact spelling and a category, plus mobile-focused additions for shadows, transitions, retro looks and motion-design treatments.

**Registered: 182. Processing code connected: 48 (status Partial). Not implemented: 134 (status Missing).**

- **Partial** = the effect has processing code connected to the Effects panel and its core tests pass, but it has not been verified in an iOS device build. None is labelled fully Working until the iOS build/runtime path is checked.
- **Missing** = only the name and category exist. These effects are not offered in the app.

Effects apply to supported visual layers, including images, video, shapes, text, solids and adjustment layers. Liquid Glass is a rendered image effect; it is distinct from the iOS system Liquid Glass interface material.

## How an effect becomes real
1. Write the processing in `ImageEffects` (pure Swift on `PixelImage`).
2. Add its settings to `EffectParameterTable` with ranges and defaults.
3. Add pixel tests with known values.
4. The registry then marks it Partial automatically. Change it to Working only after its tests have actually run and passed.

A test (`EffectRegistryTests`) checks the catalogue against a separate copy of the required list and fails if an effect claims to be finished without processing code.

## Blur and sharpen (13)

| Effect | Status | Settings |
|---|---|---|
| Box Blur | Partial | running-average box kernel, adjustable radius and edge mode |
| Directional Blur | Partial | Angle, Distance |
| Gaussian Blur | Partial | Radius, Quality, Edge handling |
| Inner Blur | Missing | not yet designed |
| Lens Blur | Missing | not yet designed |
| Mask Blur | Missing | not yet designed |
| Motion Blur | Missing | designed: Shutter angle, Samples, Quality |
| Omino Diffusion+ | Missing | not yet designed |
| Precise Box Blur | Missing | not yet designed |
| Sharpen | Partial | Amount, Radius |
| Spin Blur | Missing | not yet designed |
| Unsharp Mask | Missing | not yet designed |
| Radial Blur | Partial | Amount, centre and sample count |
| Zoom Blur | Partial | radial sample blur with configurable centre and amount |

## Glow, light and shadow (18)

| Effect | Status | Settings |
|---|---|---|
| Dark Glow | Missing | not yet designed |
| Drop Shadow | Partial | Colour, Opacity, Blur, Distance, Angle, Spread |
| Edge Glow | Partial | Edge threshold, intensity, glow radius and colour |
| Glow | Partial | Threshold, Radius, Intensity, Colour, Output |
| Glow Scan | Missing | not yet designed |
| Inner Glow | Missing | not yet designed |
| Lens Flare | Missing | not yet designed |
| Light Glow | Missing | not yet designed |
| Lightning | Missing | not yet designed |
| Linear Streaks | Missing | not yet designed |
| Long Shadow | Missing | not yet designed |
| Radial Rays | Missing | not yet designed |
| Radial Shadow | Missing | not yet designed |
| Rays | Missing | not yet designed |
| Soft Glow | Missing | not yet designed |
| Spin Streaks | Missing | not yet designed |
| Vignette | Partial | Intensity, Radius, Softness, Centre |
| Zoom Streaks | Missing | not yet designed |

## Colour (23)

| Effect | Status | Settings |
|---|---|---|
| Brightness / Contrast | Partial | Brightness, Contrast |
| Channel Remap (HSV) | Missing | not yet designed |
| Channel Remap (RGB) | Missing | not yet designed |
| Color Temperature | Missing | not yet designed |
| Color Tune | Missing | not yet designed |
| Colorize | Missing | not yet designed |
| Exposure / Gamma | Missing | not yet designed |
| Fill Behind | Missing | not yet designed |
| Gradient Map | Partial | Shadow, midtone and highlight colours, Midtone position, Mix |
| Gradient Overlay | Missing | not yet designed |
| Highlights and Shadows | Missing | not yet designed |
| Hot Color | Missing | not yet designed |
| Hue Shift | Partial | Hue shift (degrees) |
| Invert | Partial | none |
| Iridescence | Missing | not yet designed |
| Palette Map | Missing | not yet designed |
| Posterize | Partial | Levels |
| Replace Color | Missing | not yet designed |
| Saturation / Vibrance | Partial | Saturation (the Vibrance half is not implemented) |
| Spectral Map | Missing | not yet designed |
| Spot Color | Missing | not yet designed |
| Stroke Color | Missing | not yet designed |
| Threshold | Missing | not yet designed |

## Distort (28)

| Effect | Status | Settings |
|---|---|---|
| Bend | Missing | not yet designed |
| Bump Map | Missing | not yet designed |
| Circular Ripple | Missing | not yet designed |
| Copy Background | Missing | not yet designed |
| Curl | Missing | not yet designed |
| Displacement Map | Missing | designed: Horizontal, Vertical, Edge handling (map source not designed) |
| Flip Layer | Missing | not yet designed |
| Fractal Warp | Missing | not yet designed |
| Glass | Missing | not yet designed |
| Inner Pinch/Bulge | Missing | not yet designed |
| Kaleidoscope | Missing | not yet designed |
| Magnify Background | Missing | not yet designed |
| Mirror | Missing | not yet designed |
| Offset | Missing | not yet designed |
| Omino Glass | Missing | not yet designed |
| Pinch/Bulge | Missing | not yet designed |
| Polar Coordinates | Missing | not yet designed |
| Polar Displacement Map | Missing | not yet designed |
| Random Displacement | Partial | deterministic procedural displacement; no separate map input yet |
| RGB Split | Partial | Red offset, Blue offset, Intensity |
| Spherize | Missing | not yet designed |
| Squeeze | Missing | not yet designed |
| Stretch Axis | Missing | not yet designed |
| Stretch Segment | Missing | not yet designed |
| Swirl | Missing | not yet designed |
| Tunnel | Missing | not yet designed |
| Turbulent Displace | Missing | not yet designed |
| Wave Warp | Partial | Amplitude, Waves per 1000 pixels, Phase, Direction, Wave type |

## Generate (18)

| Effect | Status | Settings |
|---|---|---|
| Block Noise | Missing | not yet designed |
| Checker | Missing | not yet designed |
| Clouds | Missing | not yet designed |
| Contour Gradient | Missing | not yet designed |
| Dots | Missing | not yet designed |
| Four-color Gradient | Missing | not yet designed |
| Fractal Ridges | Missing | not yet designed |
| Grid | Missing | not yet designed |
| Heart | Missing | not yet designed |
| Hexagon Array | Missing | not yet designed |
| Noise | Partial | deterministic monochrome or colour grain with seed |
| Simple Starfield | Missing | not yet designed |
| Solid Color | Missing | not yet designed |
| Star | Missing | not yet designed |
| Starfield | Missing | not yet designed |
| Stripes | Missing | not yet designed |
| Turbulence | Missing | not yet designed |
| Voronoi Cells | Missing | not yet designed |

## Stylize (11)

| Effect | Status | Settings |
|---|---|---|
| CMYK Halftone Dots | Partial | stylised monochrome halftone screen with size, angle and contrast |
| Contour Lines | Missing | not yet designed |
| Contour Strips | Missing | not yet designed |
| Electric Edges | Missing | not yet designed |
| Find Edges | Missing | not yet designed |
| Mosaic | Missing | not yet designed |
| Pixelate | Partial | Block size |
| Raster Extrude | Missing | not yet designed |
| Ribbon | Missing | not yet designed |
| Smooth Bevel | Missing | not yet designed |
| Stroke Taper | Missing | not yet designed |

## Keying and mattes (7)

| Effect | Status | Settings |
|---|---|---|
| Chroma Key | Partial | designed: Key colour, Tolerance, Edge softness, Spill suppression |
| Feather | Missing | not yet designed |
| Luma Key | Missing | not yet designed |
| Matte Choker | Missing | not yet designed |
| Roughen Edges | Partial | deterministic alpha-edge perturbation |
| Smooth Edges | Missing | not yet designed |
| Solid Matte | Missing | not yet designed |

## Repeat and tile (12)

| Effect | Status | Settings |
|---|---|---|
| Grid Repeat | Missing | not yet designed |
| Hexagon Tile Rotate | Missing | not yet designed |
| Hexagon Tile Shift | Missing | not yet designed |
| Hexagon Tiling | Missing | not yet designed |
| Linear Repeat | Missing | not yet designed |
| Radial Repeat | Missing | not yet designed |
| Repeat | Missing | not yet designed |
| Repeat Along Path | Missing | not yet designed |
| Scatter Repeat | Missing | not yet designed |
| Tile Rotate | Missing | not yet designed |
| Tile Shift | Missing | not yet designed |
| Tiles | Missing | not yet designed |

## Transitions (6)

| Effect | Status | Settings |
|---|---|---|
| Block Dissolve | Missing | not yet designed |
| Dissolve | Missing | not yet designed |
| Drawing Progress | Missing | not yet designed |
| Fade In/Out | Missing | not yet designed |
| Radial Wipe | Missing | not yet designed |
| Wipe | Missing | not yet designed |

## Animation and time (14)

| Effect | Status | Settings |
|---|---|---|
| Auto-Shake | Missing | not yet designed |
| Blink | Missing | not yet designed |
| Count Up/Down | Missing | not yet designed |
| Echo Keyframes | Missing | not yet designed |
| Flicker | Missing | not yet designed |
| Move Along Path | Missing | not yet designed |
| Oscillate | Missing | not yet designed |
| Pulse Opacity | Missing | not yet designed |
| Pulse Size | Missing | not yet designed |
| Random Jitter | Missing | not yet designed |
| Spin | Missing | not yet designed |
| Swing | Missing | not yet designed |
| Time Quantization | Missing | not yet designed |
| Timecode | Missing | not yet designed |

## Text (4)

| Effect | Status | Settings |
|---|---|---|
| Text Progress | Missing | not yet designed |
| Text Randomizer | Missing | not yet designed |
| Text Spacing | Missing | not yet designed |
| Text Transform | Missing | not yet designed |

## 3D and 360 (14)

| Effect | Status | Settings |
|---|---|---|
| 360º Reorient Sphere | Missing | not yet designed |
| 360º Viewer | Missing | not yet designed |
| Box | Missing | not yet designed |
| Cube | Missing | not yet designed |
| Cylinder | Missing | not yet designed |
| Ellipsoid | Missing | not yet designed |
| Hexagonal Prism | Missing | not yet designed |
| Hollow Box | Missing | not yet designed |
| Octahedron | Missing | not yet designed |
| Pyramid | Missing | not yet designed |
| Star Polyhedron | Missing | not yet designed |
| Star Prism | Missing | not yet designed |
| Three-axis Cross | Missing | not yet designed |
| Torus | Missing | not yet designed |
