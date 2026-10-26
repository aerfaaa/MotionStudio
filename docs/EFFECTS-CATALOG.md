# Effects catalogue

Every effect name required by the product specification is registered in `MotionCore` (`EffectRegistry`), with its exact spelling and a category.

**Registered: 167 effects. Rendering implemented: 0.** Every effect is **Missing** because nothing renders effects yet.
Being listed here means the name, category and (for 9 effects) the setting definitions exist. It does not mean anything is drawn.

An automated test (`EffectRegistryTests`) compares the registry with a separate copy of the required list, and another test fails if any effect is marked finished before a renderer exists. `scripts/check_repository.py` repeats the name comparison without a compiler.

## How an effect will become real
1. Choose an implementation (Core Image filter, Metal shader or custom code) and write it behind the `ResolvedFrame` contract.
2. Add its parameters to `EffectParameterTable` with ranges and defaults.
3. Add a rendering test with expected pixels and a tolerance.
4. Only then change its status to Partial or Working, here and in code.

Effect names such as Omino Diffusion+ and Omino Glass are the product's own native versions. They are not copies of any third-party plugin.

## Blur and sharpen (13)

| Effect | Status | Settings designed | Notes |
|---|---|---|---|
| Box Blur | Missing | not yet | no renderer |
| Directional Blur | Missing | not yet | no renderer |
| Gaussian Blur | Missing | Radius, Quality, Edge handling | no renderer |
| Inner Blur | Missing | not yet | no renderer |
| Lens Blur | Missing | not yet | no renderer |
| Mask Blur | Missing | not yet | no renderer |
| Motion Blur | Missing | Shutter angle, Samples, Quality | no renderer |
| Omino Diffusion+ | Missing | not yet | no renderer |
| Precise Box Blur | Missing | not yet | no renderer |
| Sharpen | Missing | not yet | no renderer |
| Spin Blur | Missing | not yet | no renderer |
| Unsharp Mask | Missing | not yet | no renderer |
| Zoom Blur | Missing | not yet | no renderer |

## Glow, light and shadow (17)

| Effect | Status | Settings designed | Notes |
|---|---|---|---|
| Dark Glow | Missing | not yet | no renderer |
| Edge Glow | Missing | not yet | no renderer |
| Glow | Missing | Threshold, Radius, Intensity, Colour (red, green, blue) | no renderer |
| Glow Scan | Missing | not yet | no renderer |
| Inner Glow | Missing | not yet | no renderer |
| Lens Flare | Missing | not yet | no renderer |
| Light Glow | Missing | not yet | no renderer |
| Lightning | Missing | not yet | no renderer |
| Linear Streaks | Missing | not yet | no renderer |
| Long Shadow | Missing | not yet | no renderer |
| Radial Rays | Missing | not yet | no renderer |
| Radial Shadow | Missing | not yet | no renderer |
| Rays | Missing | not yet | no renderer |
| Soft Glow | Missing | not yet | no renderer |
| Spin Streaks | Missing | not yet | no renderer |
| Vignette | Missing | not yet | no renderer |
| Zoom Streaks | Missing | not yet | no renderer |

## Colour (23)

| Effect | Status | Settings designed | Notes |
|---|---|---|---|
| Brightness / Contrast | Missing | Brightness, Contrast | no renderer |
| Channel Remap (HSV) | Missing | not yet | no renderer |
| Channel Remap (RGB) | Missing | not yet | no renderer |
| Color Temperature | Missing | not yet | no renderer |
| Color Tune | Missing | not yet | no renderer |
| Colorize | Missing | not yet | no renderer |
| Exposure / Gamma | Missing | not yet | no renderer |
| Fill Behind | Missing | not yet | no renderer |
| Gradient Map | Missing | not yet | no renderer |
| Gradient Overlay | Missing | not yet | no renderer |
| Highlights and Shadows | Missing | not yet | no renderer |
| Hot Color | Missing | not yet | no renderer |
| Hue Shift | Missing | Hue shift (degrees) | no renderer |
| Invert | Missing | not yet | no renderer |
| Iridescence | Missing | not yet | no renderer |
| Palette Map | Missing | not yet | no renderer |
| Posterize | Missing | not yet | no renderer |
| Replace Color | Missing | not yet | no renderer |
| Saturation / Vibrance | Missing | not yet | no renderer |
| Spectral Map | Missing | not yet | no renderer |
| Spot Color | Missing | not yet | no renderer |
| Stroke Color | Missing | not yet | no renderer |
| Threshold | Missing | not yet | no renderer |

## Distort (28)

| Effect | Status | Settings designed | Notes |
|---|---|---|---|
| Bend | Missing | not yet | no renderer |
| Bump Map | Missing | not yet | no renderer |
| Circular Ripple | Missing | not yet | no renderer |
| Copy Background | Missing | not yet | no renderer |
| Curl | Missing | not yet | no renderer |
| Displacement Map | Missing | Horizontal, Vertical, Edge handling (map source layer: not designed yet) | no renderer |
| Flip Layer | Missing | not yet | no renderer |
| Fractal Warp | Missing | not yet | no renderer |
| Glass | Missing | not yet | no renderer |
| Inner Pinch/Bulge | Missing | not yet | no renderer |
| Kaleidoscope | Missing | not yet | no renderer |
| Magnify Background | Missing | not yet | no renderer |
| Mirror | Missing | not yet | no renderer |
| Offset | Missing | not yet | no renderer |
| Omino Glass | Missing | not yet | no renderer |
| Pinch/Bulge | Missing | not yet | no renderer |
| Polar Coordinates | Missing | not yet | no renderer |
| Polar Displacement Map | Missing | not yet | no renderer |
| RGB Split | Missing | Red offset, Blue offset, Intensity | no renderer |
| Random Displacement | Missing | not yet | no renderer |
| Spherize | Missing | not yet | no renderer |
| Squeeze | Missing | not yet | no renderer |
| Stretch Axis | Missing | not yet | no renderer |
| Stretch Segment | Missing | not yet | no renderer |
| Swirl | Missing | not yet | no renderer |
| Tunnel | Missing | not yet | no renderer |
| Turbulent Displace | Missing | not yet | no renderer |
| Wave Warp | Missing | Amplitude, Frequency, Phase, Direction, Wave type | no renderer |

## Generate (18)

| Effect | Status | Settings designed | Notes |
|---|---|---|---|
| Block Noise | Missing | not yet | no renderer |
| Checker | Missing | not yet | no renderer |
| Clouds | Missing | not yet | no renderer |
| Contour Gradient | Missing | not yet | no renderer |
| Dots | Missing | not yet | no renderer |
| Four-color Gradient | Missing | not yet | no renderer |
| Fractal Ridges | Missing | not yet | no renderer |
| Grid | Missing | not yet | no renderer |
| Heart | Missing | not yet | no renderer |
| Hexagon Array | Missing | not yet | no renderer |
| Noise | Missing | not yet | no renderer |
| Simple Starfield | Missing | not yet | no renderer |
| Solid Color | Missing | not yet | no renderer |
| Star | Missing | not yet | no renderer |
| Starfield | Missing | not yet | no renderer |
| Stripes | Missing | not yet | no renderer |
| Turbulence | Missing | not yet | no renderer |
| Voronoi Cells | Missing | not yet | no renderer |

## Stylize (11)

| Effect | Status | Settings designed | Notes |
|---|---|---|---|
| CMYK Halftone Dots | Missing | not yet | no renderer |
| Contour Lines | Missing | not yet | no renderer |
| Contour Strips | Missing | not yet | no renderer |
| Electric Edges | Missing | not yet | no renderer |
| Find Edges | Missing | not yet | no renderer |
| Mosaic | Missing | not yet | no renderer |
| Pixelate | Missing | not yet | no renderer |
| Raster Extrude | Missing | not yet | no renderer |
| Ribbon | Missing | not yet | no renderer |
| Smooth Bevel | Missing | not yet | no renderer |
| Stroke Taper | Missing | not yet | no renderer |

## Keying and mattes (7)

| Effect | Status | Settings designed | Notes |
|---|---|---|---|
| Chroma Key | Missing | Key colour (red, green, blue), Tolerance, Edge softness, Spill suppression | no renderer |
| Feather | Missing | not yet | no renderer |
| Luma Key | Missing | not yet | no renderer |
| Matte Choker | Missing | not yet | no renderer |
| Roughen Edges | Missing | not yet | no renderer |
| Smooth Edges | Missing | not yet | no renderer |
| Solid Matte | Missing | not yet | no renderer |

## Repeat and tile (12)

| Effect | Status | Settings designed | Notes |
|---|---|---|---|
| Grid Repeat | Missing | not yet | no renderer |
| Hexagon Tile Rotate | Missing | not yet | no renderer |
| Hexagon Tile Shift | Missing | not yet | no renderer |
| Hexagon Tiling | Missing | not yet | no renderer |
| Linear Repeat | Missing | not yet | no renderer |
| Radial Repeat | Missing | not yet | no renderer |
| Repeat | Missing | not yet | no renderer |
| Repeat Along Path | Missing | not yet | no renderer |
| Scatter Repeat | Missing | not yet | no renderer |
| Tile Rotate | Missing | not yet | no renderer |
| Tile Shift | Missing | not yet | no renderer |
| Tiles | Missing | not yet | no renderer |

## Transitions (6)

| Effect | Status | Settings designed | Notes |
|---|---|---|---|
| Block Dissolve | Missing | not yet | no renderer |
| Dissolve | Missing | not yet | no renderer |
| Drawing Progress | Missing | not yet | no renderer |
| Fade In/Out | Missing | not yet | no renderer |
| Radial Wipe | Missing | not yet | no renderer |
| Wipe | Missing | not yet | no renderer |

## Animation and time (14)

| Effect | Status | Settings designed | Notes |
|---|---|---|---|
| Auto-Shake | Missing | not yet | no renderer |
| Blink | Missing | not yet | no renderer |
| Count Up/Down | Missing | not yet | no renderer |
| Echo Keyframes | Missing | not yet | no renderer |
| Flicker | Missing | not yet | no renderer |
| Move Along Path | Missing | not yet | no renderer |
| Oscillate | Missing | not yet | no renderer |
| Pulse Opacity | Missing | not yet | no renderer |
| Pulse Size | Missing | not yet | no renderer |
| Random Jitter | Missing | not yet | no renderer |
| Spin | Missing | not yet | no renderer |
| Swing | Missing | not yet | no renderer |
| Time Quantization | Missing | not yet | no renderer |
| Timecode | Missing | not yet | no renderer |

## Text (4)

| Effect | Status | Settings designed | Notes |
|---|---|---|---|
| Text Progress | Missing | not yet | no renderer |
| Text Randomizer | Missing | not yet | no renderer |
| Text Spacing | Missing | not yet | no renderer |
| Text Transform | Missing | not yet | no renderer |

## 3D and 360 (14)

| Effect | Status | Settings designed | Notes |
|---|---|---|---|
| 360º Reorient Sphere | Missing | not yet | no renderer |
| 360º Viewer | Missing | not yet | no renderer |
| Box | Missing | not yet | no renderer |
| Cube | Missing | not yet | no renderer |
| Cylinder | Missing | not yet | no renderer |
| Ellipsoid | Missing | not yet | no renderer |
| Hexagonal Prism | Missing | not yet | no renderer |
| Hollow Box | Missing | not yet | no renderer |
| Octahedron | Missing | not yet | no renderer |
| Pyramid | Missing | not yet | no renderer |
| Star Polyhedron | Missing | not yet | no renderer |
| Star Prism | Missing | not yet | no renderer |
| Three-axis Cross | Missing | not yet | no renderer |
| Torus | Missing | not yet | no renderer |
