import Foundation
import MotionCore

/// Human-friendly descriptions and SF Symbols for the effects browser.
/// Every catalogue entry gets a description and an icon, including effects not implemented yet.
enum EffectLibraryMetadata {
    static func categorySymbol(_ category: EffectCategory) -> String {
        switch category {
        case .blurSharpen: return "aqi.medium"
        case .light: return "sun.max.fill"
        case .color: return "paintpalette.fill"
        case .distort: return "water.waves"
        case .generate: return "sparkles.rectangle.stack"
        case .stylize: return "wand.and.stars"
        case .keyingMatte: return "person.crop.rectangle"
        case .repeatTile: return "square.grid.3x3.fill"
        case .transition: return "arrow.left.arrow.right"
        case .animation: return "figure.run"
        case .text: return "textformat"
        case .threeD: return "cube.transparent.fill"
        }
    }

    static func symbol(for effect: EffectDefinition) -> String {
        let id = effect.id
        let exact: [String: String] = [
            "box-blur":"square.stack.3d.down.right", "gaussian-blur":"circle.dotted", "directional-blur":"arrow.right", "motion-blur":"figure.run", "optical-flow-slow-motion":"speedometer",
            "sharpen":"viewfinder", "unsharp-mask":"scope", "zoom-blur":"arrow.up.left.and.arrow.down.right", "spin-blur":"arrow.trianglehead.2.clockwise.rotate.90",
            "glow":"sun.max.fill", "bloom":"sun.max.fill", "duotone":"circle.lefthalf.filled", "glitch-lines":"waveform.path.ecg", "soft-glow":"sun.haze.fill", "drop-shadow":"shadow", "long-shadow":"rectangle.portrait.arrowtriangle.2.outward",
            "vignette":"circle.dashed.inset.filled", "lens-flare":"sun.max", "lightning":"bolt.fill", "radial-rays":"sun.rays.fill",
            "brightness-contrast":"circle.lefthalf.filled", "color-temperature":"thermometer.medium", "hue-shift":"circle.lefthalf.striped.horizontal", "saturation-vibrance":"paintpalette.fill",
            "gradient-map":"point.3.connected.trianglepath.dotted", "gradient-overlay":"circle.lefthalf.filled", "invert":"circle.lefthalf.filled.inverse", "posterize":"square.3.layers.3d",
            "rgb-split":"eyedropper.halffull", "chromatic-aberration":"rainbow", "wave-warp":"water.waves", "swirl":"tornado", "kaleidoscope":"view.2d", "mirror":"rectangle.lefthalf.inset.filled",
            "pinch-bulge":"arrow.down.left.and.arrow.up.right", "circular-ripple":"water.waves", "random-displacement":"shuffle", "stretch-segment":"arrow.left.and.right.righttriangle.left.righttriangle.right.fill",
            "noise":"aqi.low", "block-noise":"square.grid.3x3.fill", "clouds":"cloud.fill", "checker":"checkerboard.rectangle", "grid":"grid", "dots":"circle.grid.3x3.fill",
            "four-color-gradient":"circle.hexagongrid.fill", "starfield":"sparkles", "simple-starfield":"star.fill", "voronoi-cells":"hexagon.grid.fill",
            "cmyk-halftone-dots":"circle.grid.3x3.fill", "pixelate":"square.grid.3x3", "mosaic":"square.grid.3x3.fill", "electric-edges":"bolt.horizontal.fill", "find-edges":"scribble.variable",
            "chroma-key":"person.crop.rectangle.stack", "luma-key":"circle.lefthalf.filled", "roughen-edges":"scribble", "feather":"feather.fill", "smooth-edges":"circle.dotted",
            "radial-repeat":"circle.hexagongrid.fill", "linear-repeat":"square.stack.3d.up.fill", "scatter-repeat":"sparkles", "tiles":"square.grid.3x3.fill", "motion-tile":"square.split.2x2.fill",
            "dissolve":"aqi.low", "block-dissolve":"square.grid.3x3.fill", "fade-in-out":"circle.lefthalf.filled", "radial-wipe":"circle.dashed.inset.filled", "wipe":"arrow.right.to.line",
            "auto-shake":"waveform.path", "blink":"light.beacon.max.fill", "flicker":"lightbulb.2.fill", "pulse-opacity":"waveform", "pulse-size":"arrow.up.left.and.arrow.down.right",
            "spin":"arrow.trianglehead.2.clockwise.rotate.90", "swing":"arrow.left.and.right", "timecode":"timer", "count-up-down":"number",
            "text-progress":"text.line.first.and.arrowtriangle.forward", "text-randomizer":"character.cursor.ibeam", "text-spacing":"textformat.size", "text-transform":"textformat.abc",
            "cube":"cube.fill", "cylinder":"cylinder.fill", "sphere":"globe", "ellipsoid":"oval.portrait.fill", "torus":"circle.hexagongrid.fill",
            "film-grain":"film", "scanlines":"tv", "vhs":"tv.and.hifispeaker.fill",
            "liquid-glass":"drop.fill", "edge-glow":"sparkles", "radial-blur":"circle.dashed.inset.filled", "black-white":"circle.lefthalf.filled", "sepia-tone":"camera.filters", "solarize":"sun.max.trianglebadge.exclamationmark"
        ]
        if let symbol = exact[id] { return symbol }
        let name = effect.name.lowercased()
        if name.contains("blur") { return "aqi.medium" }
        if name.contains("glow") || name.contains("ray") || name.contains("light") { return "sun.max.fill" }
        if name.contains("color") || name.contains("colour") || name.contains("hue") || name.contains("saturation") || name.contains("gradient") { return "paintpalette.fill" }
        if name.contains("repeat") || name.contains("tile") { return "square.grid.3x3.fill" }
        if name.contains("text") { return "textformat" }
        if name.contains("key") || name.contains("matte") || name.contains("edge") { return "person.crop.rectangle" }
        if name.contains("wave") || name.contains("ripple") || name.contains("warp") || name.contains("displace") { return "water.waves" }
        if name.contains("star") || name.contains("heart") || name.contains("cloud") || name.contains("noise") { return "sparkles" }
        if name.contains("3d") || name.contains("cube") || name.contains("box") || name.contains("sphere") || name.contains("prism") { return "cube.transparent.fill" }
        if name.contains("fade") || name.contains("wipe") || name.contains("dissolve") || name.contains("transition") { return "arrow.left.arrow.right" }
        if name.contains("spin") || name.contains("shake") || name.contains("move") || name.contains("swing") || name.contains("pulse") { return "waveform.path" }
        return categorySymbol(effect.category)
    }

    static func summary(for effect: EffectDefinition) -> String {
        let id = effect.id
        let descriptions: [String: String] = [
            "360-reorient-sphere":"Reorient spherical 360° footage to change the viewing direction.",
            "360-viewer":"Preview panoramic footage as an immersive spherical scene.",
            "auto-shake":"Adds automatic camera-like movement for handheld energy.",
            "bend":"Bends the layer along a curve for a flexible, warped shape.",
            "blink":"Turns visibility on and off in repeated pulses.",
            "block-dissolve":"Reveals or removes the layer in a pattern of square blocks.",
            "block-noise":"Creates chunky digital noise and blocky texture.",
            "box-blur":"Softens details by averaging neighbouring pixels.",
            "brightness-contrast":"Adjusts overall lightness and the separation between dark and bright tones.",
            "bump-map":"Uses surface brightness to create a raised, embossed depth illusion.",
            "cmyk-halftone-dots":"Converts the image into a print-like pattern of halftone dots.",
            "channel-remap-hsv":"Remaps hue, saturation and value channels for colour-channel experimentation.",
            "channel-remap-rgb":"Reassigns red, green and blue channels to create custom colour mixes.",
            "checker":"Generates a repeating checkerboard pattern.",
            "chroma-key":"Removes a selected colour, commonly green screen, to make it transparent.",
            "circular-ripple":"Distorts the image with expanding circular ripples.",
            "clouds":"Generates cloudy, soft-edged noise textures.",
            "color-temperature":"Warms an image toward orange or cools it toward blue.",
            "color-tune":"Fine-tunes hue, saturation and brightness in one adjustable colour pass.",
            "bloom":"Adds a soft highlight bloom with adjustable threshold, radius and intensity.",
            "duotone":"Maps shadows and highlights to two editable colours.",
            "glitch-lines":"Offsets horizontal bands for a controlled digital glitch.",
            "glow-scan":"Combines CRT scan bands with a soft highlight glow for retro-screen looks.",
            "colorize":"Applies colour to a monochrome or grayscale image.",
            "contour-gradient":"Creates a gradient that follows contour-like shapes.",
            "contour-lines":"Draws lines around image tones like a topographic map.",
            "contour-strips":"Turns tonal contours into bold, banded strips.",
            "copy-background":"Copies the composition background into the effect result.",
            "count-up-down":"Animates a number counting up or down over time.",
            "curl":"Curls the layer as if its surface were bending or peeling.",
            "dark-glow":"Adds a dark halo or shadow-like glow around bright areas.",
            "directional-blur":"Blurs pixels along a chosen direction to suggest movement.",
            "displacement-map":"Warps pixels according to values from a displacement map.",
            "dissolve":"Fades the layer away by progressively breaking up its opacity.",
            "dots":"Generates a regular dot pattern for graphic backgrounds.",
            "drawing-progress":"Animates a stroke or drawing from its start to its end.",
            "echo-keyframes":"Creates trailing echoes from earlier animated positions.",
            "edge-glow":"Highlights edges with a luminous outline.",
            "electric-edges":"Turns outlines into bright, electric-looking edges.",
            "exposure-gamma":"Adjusts exposure and midtone response for brightness control.",
            "fade-in-out":"Animates opacity in and/or out over the layer's duration.",
            "feather":"Softens a matte boundary for a smoother composite.",
            "fill-behind":"Fills the area behind the layer with a colour or backdrop.",
            "find-edges":"Detects and highlights boundaries in the image.",
            "flicker":"Adds irregular brightness changes like a flickering light.",
            "flip-layer":"Flips the layer horizontally or vertically.",
            "four-color-gradient":"Creates a blend between four independently coloured corners.",
            "fractal-ridges":"Generates layered, ridge-like fractal texture.",
            "fractal-warp":"Distorts the layer using complex fractal patterns.",
            "gaussian-blur":"Produces smooth, natural blur with a Gaussian falloff.",
            "glass":"Adds a glass-like refraction or distortion treatment.",
            "liquid-glass":"Bends the image through a glossy, rounded lens with a subtle refractive highlight.",
            "radial-blur":"Blurs pixels toward or away from a chosen centre to suggest zooming motion.",
            "glow":"Adds a configurable halo around bright image details.",
            "glow-scan":"Sweeps a glowing scan line across the layer.",
            "gradient-map":"Maps dark, midtone and bright values to chosen colours.",
            "gradient-overlay":"Layers a colour gradient over the image.",
            "grid":"Generates a clean grid of horizontal and vertical lines.",
            "grid-repeat":"Repeats the layer in a grid arrangement.",
            "heart":"Generates a heart shape for graphic compositions.",
            "hexagon-array":"Creates an array of hexagons.",
            "hexagon-tile-rotate":"Repeats hexagonal tiles with rotation.",
            "hexagon-tile-shift":"Offsets rows or columns of hexagonal tiles.",
            "hexagon-tiling":"Tiles the image in a hexagonal pattern.",
            "highlights-and-shadows":"Recovers or deepens bright and dark regions independently.",
            "hot-color":"Maps image intensity to a high-contrast heat palette.",
            "hue-shift":"Rotates colours around the hue wheel.",
            "inner-blur":"Softens details inside the layer's visible boundary.",
            "inner-glow":"Adds light along the inside edge of a shape or image.",
            "inner-pinch-bulge":"Pinches or bulges pixels within the inner region.",
            "invert":"Reverses image colours to create a negative.",
            "iridescence":"Adds shifting, pearlescent rainbow colour.",
            "kaleidoscope":"Mirrors repeated wedges into a kaleidoscopic pattern.",
            "lens-blur":"Simulates optical lens defocus with softer highlights.",
            "lens-flare":"Adds a camera-lens flare from a bright light source.",
            "light-glow":"Adds a soft luminous bloom to bright areas.",
            "lightning":"Generates lightning-like bolts for dramatic accents.",
            "linear-repeat":"Repeats the layer in a straight line.",
            "linear-streaks":"Creates elongated light streaks in a linear direction.",
            "long-shadow":"Extends a long, directional shadow from opaque areas.",
            "luma-key":"Uses brightness to remove or preserve parts of the image.",
            "magnify-background":"Magnifies the background through a selected region.",
            "mask-blur":"Blurs selectively according to a mask.",
            "matte-choker":"Contracts or tightens a matte to remove edge spill.",
            "mirror":"Reflects the image across a chosen axis.",
            "mosaic":"Groups pixels into larger colour blocks like a mosaic.",
            "motion-blur":"Adds directional blur based on movement and shutter feel.",
            "optical-flow-slow-motion":"Synthesizes in-between video frames from Vision motion estimates when a video layer is slowed down. Export-time processing is heavier than ordinary effects.",
            "move-along-path":"Animates a layer along a chosen motion path.",
            "noise":"Adds controlled monochrome or coloured grain.",
            "offset":"Shifts image content horizontally or vertically, wrapping edges.",
            "omino-diffusion":"Diffuses detail into a soft, painterly texture.",
            "omino-glass":"Creates a glassy, refracted image treatment.",
            "oscillate":"Moves a property back and forth repeatedly.",
            "palette-map":"Maps image tones to a selected colour palette.",
            "pinch-bulge":"Pulls pixels inward or pushes them outward from a centre.",
            "pixelate":"Reduces detail into visible square pixels.",
            "polar-coordinates":"Remaps rectangular imagery into polar or circular coordinates.",
            "polar-displacement-map":"Applies displacement in a polar coordinate space.",
            "posterize":"Reduces the number of tonal levels for a graphic look.",
            "precise-box-blur":"Applies a controlled box blur with predictable radius.",
            "pulse-opacity":"Pulses transparency rhythmically.",
            "pulse-size":"Pulses scale rhythmically for a breathing effect.",
            "rgb-split":"Offsets red and blue channels for a colour-fringe glitch.",
            "radial-rays":"Projects rays outward from a central point.",
            "radial-repeat":"Repeats the layer around a circular centre.",
            "radial-shadow":"Projects a shadow outward from a central point.",
            "radial-wipe":"Reveals the layer using a rotating circular wipe.",
            "random-displacement":"Jitters pixels with a repeatable random warp.",
            "random-jitter":"Adds small random movement to animated properties.",
            "raster-extrude":"Extrudes image details into a pixel-based dimensional effect.",
            "rays":"Adds beams of light extending from a source.",
            "repeat":"Duplicates the layer repeatedly.",
            "repeat-along-path":"Repeats the layer along a path.",
            "replace-color":"Replaces a target colour with another colour.",
            "ribbon":"Stylizes shapes or strokes into flowing ribbon-like forms.",
            "roughen-edges":"Breaks up smooth alpha edges with an irregular texture.",
            "saturation-vibrance":"Controls colour intensity, from muted to vivid.",
            "scatter-repeat":"Repeats copies with scattered positions and spacing.",
            "sharpen":"Enhances local contrast to make details appear crisper.",
            "simple-starfield":"Generates a lightweight field of stars.",
            "smooth-bevel":"Adds a soft bevel to suggest rounded depth.",
            "smooth-edges":"Softens jagged edges while preserving the silhouette.",
            "soft-glow":"Adds a gentle bloom for a dreamy, diffused look.",
            "solid-color":"Generates a flat colour layer.",
            "solid-matte":"Creates a solid opaque or transparent matte.",
            "spectral-map":"Maps tones to a spectrum-inspired colour range.",
            "spherize":"Bends a flat image around a spherical surface.",
            "spin":"Rotates a layer over time.",
            "spin-blur":"Blurs around a centre to simulate rotational movement.",
            "spin-streaks":"Creates curved light streaks around a centre.",
            "spot-color":"Keeps or emphasizes a selected colour in the image.",
            "squeeze":"Compresses the image along an axis.",
            "star":"Generates a star shape.",
            "starfield":"Generates a field of stars for space scenes.",
            "stretch-axis":"Stretches the layer along a chosen axis.",
            "stretch-segment":"Stretches a selected segment of the image.",
            "stripes":"Generates repeating stripes.",
            "stroke-color":"Applies a colour treatment to a stroke or outline.",
            "stroke-taper":"Tapers a stroke so its ends become thinner.",
            "swing":"Animates a layer swinging around an anchor point.",
            "swirl":"Twists pixels around a central point.",
            "text-progress":"Reveals or hides text progressively over time.",
            "text-randomizer":"Randomizes text characters for a changing typographic effect.",
            "text-spacing":"Adjusts spacing between characters or lines.",
            "text-transform":"Applies a transform treatment to text.",
            "threshold":"Converts tones into a high-contrast black-and-white result.",
            "tile-rotate":"Rotates repeated image tiles.",
            "tile-shift":"Offsets tiles to change the pattern alignment.",
            "tiles":"Repeats the image as a tiled surface.",
            "time-quantization":"Restricts animation updates to stepped time intervals.",
            "timecode":"Displays a running timecode readout.",
            "tunnel":"Warps imagery into a tunnel-like perspective.",
            "turbulence":"Generates organic, turbulent noise patterns.",
            "turbulent-displace":"Warps the image using flowing turbulence.",
            "unsharp-mask":"Sharpens details by enhancing contrast around edges.",
            "vignette":"Darkens or softens the frame edges to focus attention inward.",
            "voronoi-cells":"Generates polygonal cells from scattered points.",
            "wave-warp":"Bends the image with adjustable wave patterns.",
            "wipe":"Reveals or hides the layer across a straight boundary.",
            "zoom-blur":"Blurs outward from or inward toward a focal point.",
            "zoom-streaks":"Creates radial streaks that rush toward or away from a centre.",
            "drop-shadow":"Adds a cast shadow behind the layer.",
            "luma-fade":"Fades visibility according to image brightness.",
            "vhs":"Adds analogue tape colour shifts, noise and scan-line character.",
            "pixel-sort":"Reorders pixels into streaks based on colour or brightness.",
            "rgb-blur":"Blurs colour channels for a soft chromatic smear.",
            "motion-tile":"Extends repeated image edges to support movement and blur.",
            "black-white":"Converts the image to monochrome.",
            "sepia-tone":"Adds warm brown tones reminiscent of vintage photography.",
            "solarize":"Inverts selected tonal ranges for a surreal photographic look.",
            "tint":"Tints the image with a chosen colour.",
            "chromatic-aberration":"Separates colour channels near edges for a lens-like fringe.",
            "film-grain":"Adds fine film-like grain and texture.",
            "scanlines":"Overlays horizontal lines for a retro display look."
        ]
        if let description = descriptions[id] { return description }
        return fallback(for: effect)
    }

    private static func fallback(for effect: EffectDefinition) -> String {
        let name = effect.name.lowercased()
        switch effect.category {
        case .blurSharpen: return "Controls image softness or edge detail with the \(effect.name.lowercased()) treatment."
        case .light: return "Shapes highlights, illumination or shadows using a \(effect.name.lowercased()) look."
        case .color: return "Changes colour, tone or tonal mapping with \(effect.name.lowercased())."
        case .distort: return "Warps, shifts or reshapes image pixels using \(effect.name.lowercased())."
        case .generate: return "Creates a new pattern or texture: \(effect.name.lowercased())."
        case .stylize: return "Gives the layer a distinctive graphic finish with \(effect.name.lowercased())."
        case .keyingMatte: return "Refines transparency, silhouettes or matte edges using \(effect.name.lowercased())."
        case .repeatTile: return "Duplicates or rearranges image content using \(effect.name.lowercased())."
        case .transition: return "Controls how a layer is revealed or removed using \(effect.name.lowercased())."
        case .animation: return "Animates a property or changes its behaviour over time with \(effect.name.lowercased())."
        case .text: return "Changes the appearance or animation of text with \(effect.name.lowercased())."
        case .threeD: return "Creates or transforms a three-dimensional form: \(effect.name.lowercased())."
        }
    }
}
