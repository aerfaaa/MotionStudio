import Foundation

/// The processing code for each effect. Each one takes a picture, the effect's settings and the scale
/// (bitmap pixels per layer pixel) and returns a new picture. Nothing here touches the screen.
public enum ImageEffects {
    typealias Processor = (PixelImage, EffectValues, Double) -> PixelImage

    /// The largest border (in bitmap pixels) an effect may add around a picture. It keeps memory use bounded.
    static let maximumMargin = 200

    private static let table: [String: Processor] = [
        // Temporal processing is performed by the AVFoundation/Vision frame provider. This identity
        // processor makes the effect available in the shared effect browser without altering pixels.
        "optical-flow-slow-motion": identity,
        "brightness-contrast": brightnessContrast,
        "hue-shift": hueShift,
        "saturation-vibrance": saturation,
        "invert": invert,
        "black-white": blackWhite,
        "sepia-tone": sepiaTone,
        "solarize": solarize,
        "tint": tint,
        "gaussian-blur": gaussianBlur,
        "sharpen": sharpen,
        "vignette": vignette,
        "drop-shadow": dropShadow,
        "glow": glow,
        "gradient-map": gradientMap,
        "rgb-split": rgbSplit,
        "pixelate": pixelate,
        "posterize": posterize,
        "directional-blur": directionalBlur,
        "wave-warp": waveWarp,
        "chroma-key": chromaKey,
        "box-blur": boxBlur,
        "zoom-blur": zoomBlur,
        "noise": noise,
        "cmyk-halftone-dots": halftoneDots,
        "roughen-edges": roughenEdges,
        "random-displacement": randomDisplacement,
        "lens-blur": lensBlur,
        "threshold": threshold,
        "luma-fade": lumaFade,
        "vhs": vhs,
        "pixel-sort": pixelSort,
        "rgb-blur": rgbBlur,
        "motion-tile": motionTile,
        "motion-blur": motionBlur,
        "displacement-map": displacementMap,
        "color-temperature": colorTemperature,
        "colorize": colorize,
        "exposure-gamma": exposureGamma,
        "find-edges": findEdges,
        "flip-layer": flipLayer,
        "mirror": mirror,
        "mosaic": pixelate,
        "chromatic-aberration": chromaticAberration,
        "film-grain": filmGrain,
        "scanlines": scanlines,
        "liquid-glass": liquidGlass,
        "edge-glow": edgeGlow,
        "radial-blur": radialBlur,
    ]

    /// True when the effect has real processing code connected.
    public static func isAvailable(_ id: String) -> Bool { table[id] != nil }

    public static var availableIDs: [String] { table.keys.sorted() }

    static func processor(for id: String) -> Processor? { table[id] }

    // MARK: - Liquid Glass

    /// A refractive, rounded-glass lens with a restrained edge highlight. This is a raster effect,
    /// not the operating-system UI material, so it can be applied to any visual layer and exported.
    private static func liquidGlass(_ image: PixelImage, _ v: EffectValues, _ scale: Double) -> PixelImage {
        guard !image.isEmpty else { return image }
        let refraction = v.scalar("refraction") * scale
        let edgeStrength = Float(v.scalar("edge"))
        let smoothness = max(0.1, v.scalar("roundness"))
        let cx = Double(image.width) * 0.5, cy = Double(image.height) * 0.5
        var result = image
        for y in 0..<image.height {
            for x in 0..<image.width {
                let dx = (Double(x) + 0.5 - cx) / max(cx, 1)
                let dy = (Double(y) + 0.5 - cy) / max(cy, 1)
                let r = sqrt(dx * dx + dy * dy)
                let lens = exp(-pow(r * 2.2, smoothness))
                let nx = dx / max(r, 0.001), ny = dy / max(r, 0.001)
                let offset = refraction * lens
                let p = image.sample(x: Double(x) + 0.5 - nx * offset, y: Double(y) + 0.5 - ny * offset)
                let rim = Float(smoothstep(0.48, 0.78, r)) * edgeStrength * Float(lens)
                let shine = Float(max(0, 1 - abs((dx + dy * 0.72) - 0.12) * 18)) * rim * 0.22
                let alpha = p.a
                result.setPixel(x, y, r: min(alpha, p.r + shine * alpha),
                                g: min(alpha, p.g + shine * alpha), b: min(alpha, p.b + shine * alpha), a: alpha)
            }
        }
        return result
    }

    // MARK: - Edge Glow

    private static func edgeGlow(_ image: PixelImage, _ v: EffectValues, _ scale: Double) -> PixelImage {
        guard !image.isEmpty else { return image }
        let intensity = Float(v.scalar("intensity"))
        let threshold = Float(v.scalar("threshold"))
        let radius = max(0, v.scalar("radius") * scale)
        let blur = radius > 0.5 ? blurred(image, sigma: radius, passes: 2, clampEdges: true) : image
        let tint = (Float(v.scalar("colorRed")), Float(v.scalar("colorGreen")), Float(v.scalar("colorBlue")))
        var result = image
        func grey(_ x: Int, _ y: Int) -> Float {
            let p = image.straight(min(max(x, 0), image.width - 1), min(max(y, 0), image.height - 1))
            return luma(p.r, p.g, p.b)
        }
        for y in 0..<image.height {
            for x in 0..<image.width {
                let gx = abs(grey(x + 1, y) - grey(x - 1, y))
                let gy = abs(grey(x, y + 1) - grey(x, y - 1))
                let edge = max(0, min(1, (gx + gy) * 1.8 - threshold)) * intensity
                let base = image.pixel(x, y), glow = blur.pixel(x, y)
                result.setPixel(x, y, r: min(base.a, base.r + tint.0 * glow.r * edge),
                                g: min(base.a, base.g + tint.1 * glow.g * edge),
                                b: min(base.a, base.b + tint.2 * glow.b * edge), a: base.a)
            }
        }
        return result
    }

    // MARK: - Radial Blur

    private static func radialBlur(_ image: PixelImage, _ v: EffectValues, _ scale: Double) -> PixelImage {
        guard !image.isEmpty else { return image }
        let amount = v.scalar("amount")
        guard amount > 0 else { return image }
        let centre = v.vector("center")
        let cx = centre.x * Double(image.width), cy = centre.y * Double(image.height)
        let samples = min(16, max(2, Int(v.scalar("samples").rounded())))
        var result = image
        for y in 0..<image.height {
            for x in 0..<image.width {
                var r: Float = 0, g: Float = 0, b: Float = 0, a: Float = 0
                for sample in 0..<samples {
                    let t = Double(sample) / Double(max(1, samples - 1)) * amount
                    let sx = Double(x) + 0.5 + (cx - (Double(x) + 0.5)) * t
                    let sy = Double(y) + 0.5 + (cy - (Double(y) + 0.5)) * t
                    let p = image.sample(x: sx, y: sy)
                    r += p.r; g += p.g; b += p.b; a += p.a
                }
                let inv = 1 / Float(samples)
                result.setPixel(x, y, r: r * inv, g: g * inv, b: b * inv, a: a * inv)
            }
        }
        return result
    }

    // MARK: - Small helpers

    @inline(__always)
    private static func luma(_ r: Float, _ g: Float, _ b: Float) -> Float {
        0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    private static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    // MARK: - 1. Brightness / Contrast

    /// brightness shifts every colour; contrast pushes colours away from (or toward) middle grey.
    /// Contrast uses a factor of 2^(2 x contrast): 0 gives 1 (no change), 1 gives 4, -1 gives 0.25.
    private static func brightnessContrast(_ image: PixelImage, _ v: EffectValues, _ scale: Double) -> PixelImage {
        let brightness = Float(v.scalar("brightness"))
        let contrast = v.scalar("contrast")
        if brightness == 0 && contrast == 0 { return image }
        let factor = Float(pow(2.0, contrast * 2))
        return image.mapColors { r, g, b in
            ((r - 0.5) * factor + 0.5 + brightness,
             (g - 0.5) * factor + 0.5 + brightness,
             (b - 0.5) * factor + 0.5 + brightness)
        }
    }

    // MARK: - 2. Hue Shift

    static func rgbToHSV(_ r: Float, _ g: Float, _ b: Float) -> (h: Float, s: Float, v: Float) {
        let maximum = max(r, g, b)
        let minimum = min(r, g, b)
        let delta = maximum - minimum
        var hue: Float = 0
        if delta > 0 {
            if maximum == r {
                hue = (g - b) / delta
            } else if maximum == g {
                hue = 2 + (b - r) / delta
            } else {
                hue = 4 + (r - g) / delta
            }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        return (hue, maximum == 0 ? 0 : delta / maximum, maximum)
    }

    static func hsvToRGB(_ h: Float, _ s: Float, _ v: Float) -> (Float, Float, Float) {
        let scaled = h * 6
        let sector = scaled.rounded(.down)
        let fraction = scaled - sector
        let p = v * (1 - s)
        let q = v * (1 - s * fraction)
        let t = v * (1 - s * (1 - fraction))
        switch Int(sector) % 6 {
        case 0: return (v, t, p)
        case 1: return (q, v, p)
        case 2: return (p, v, t)
        case 3: return (p, q, v)
        case 4: return (t, p, v)
        default: return (v, p, q)
        }
    }

    /// Turns every hue around the colour wheel. Brightness and saturation are kept, so nothing is clipped.
    private static func hueShift(_ image: PixelImage, _ v: EffectValues, _ scale: Double) -> PixelImage {
        let degrees = v.scalar("degrees")
        if degrees == 0 { return image }
        let turn = Float(degrees / 360)
        return image.mapColors { r, g, b in
            var hsv = rgbToHSV(r, g, b)
            hsv.h += turn
            hsv.h -= hsv.h.rounded(.down)
            return hsvToRGB(hsv.h, hsv.s, hsv.v)
        }
    }

    // MARK: - 3. Saturation

    /// 0 is grey, 1 is unchanged, above 1 is more colourful. Grey is measured with Rec. 709 luma.
    /// (Only saturation is implemented. The "Vibrance" half of the catalogue name is not.)
    private static func saturation(_ image: PixelImage, _ v: EffectValues, _ scale: Double) -> PixelImage {
        let amount = Float(v.scalar("saturation"))
        if amount == 1 { return image }
        return image.mapColors { r, g, b in
            let grey = luma(r, g, b)
            return (grey + (r - grey) * amount, grey + (g - grey) * amount, grey + (b - grey) * amount)
        }
    }

    // MARK: - 4. Invert

    private static func invert(_ image: PixelImage, _ v: EffectValues, _ scale: Double) -> PixelImage {
        image.mapColors { r, g, b in (1 - r, 1 - g, 1 - b) }
    }

    // MARK: - Additional accessible colour effects

    private static func blackWhite(_ image: PixelImage, _ v: EffectValues, _ scale: Double) -> PixelImage {
        let amount = Float(v.scalar("mix"))
        return image.mapColors { r, g, b in
            let grey = luma(r, g, b)
            return (r + (grey - r) * amount, g + (grey - g) * amount, b + (grey - b) * amount)
        }
    }

    private static func sepiaTone(_ image: PixelImage, _ v: EffectValues, _ scale: Double) -> PixelImage {
        let amount = Float(v.scalar("amount"))
        return image.mapColors { r, g, b in
            let sr = min(1, 0.393 * r + 0.769 * g + 0.189 * b)
            let sg = min(1, 0.349 * r + 0.686 * g + 0.168 * b)
            let sb = min(1, 0.272 * r + 0.534 * g + 0.131 * b)
            return (r + (sr - r) * amount, g + (sg - g) * amount, b + (sb - b) * amount)
        }
    }

    private static func solarize(_ image: PixelImage, _ v: EffectValues, _ scale: Double) -> PixelImage {
        let threshold = Float(v.scalar("threshold"))
        let amount = Float(v.scalar("amount"))
        return image.mapColors { r, g, b in
            func channel(_ value: Float) -> Float {
                let solar = value >= threshold ? 1 - value : value
                return value + (solar - value) * amount
            }
            return (channel(r), channel(g), channel(b))
        }
    }

    private static func tint(_ image: PixelImage, _ v: EffectValues, _ scale: Double) -> PixelImage {
        let tr = Float(v.scalar("tintRed")), tg = Float(v.scalar("tintGreen")), tb = Float(v.scalar("tintBlue"))
        let amount = Float(v.scalar("amount"))
        return image.mapColors { r, g, b in
            (r + (tr - r) * amount, g + (tg - g) * amount, b + (tb - b) * amount)
        }
    }

    // MARK: - Blur building blocks

    /// Box widths whose repeated use approximates a Gaussian blur of the given sigma.
    static func boxRadii(sigma: Double, passes: Int) -> [Int] {
        let n = Double(passes)
        let ideal = (12 * sigma * sigma / n + 1).squareRoot()
        var lower = Int(ideal.rounded(.down))
        if lower % 2 == 0 { lower -= 1 }
        lower = max(lower, 1)
        let upper = lower + 2
        let l = Double(lower)
        let m = ((12 * sigma * sigma - n * l * l - 4 * n * l - 3 * n) / (-4 * l - 4)).rounded()
        return (0..<passes).map { index in
            let size = Double(index) < m ? lower : upper
            return (size - 1) / 2
        }
    }

    /// One running-average pass along rows or columns of all four channels.
    private static func boxPass(_ source: [Float], width: Int, height: Int, radius: Int,
                                horizontal: Bool, clampEdges: Bool) -> [Float] {
        if radius <= 0 { return source }
        var output = source
        let length = horizontal ? width : height
        let lines = horizontal ? height : width
        let step = horizontal ? 4 : width * 4
        let lineStep = horizontal ? width * 4 : 4
        let window = Double(2 * radius + 1)
        for line in 0..<lines {
            for channel in 0..<4 {
                let base = line * lineStep + channel
                func value(_ i: Int) -> Double {
                    if i < 0 { return clampEdges ? Double(source[base]) : 0 }
                    if i >= length { return clampEdges ? Double(source[base + (length - 1) * step]) : 0 }
                    return Double(source[base + i * step])
                }
                var sum = 0.0
                for i in -radius...radius { sum += value(i) }
                for position in 0..<length {
                    output[base + position * step] = Float(sum / window)
                    sum += value(position + radius + 1) - value(position - radius)
                }
            }
        }
        return output
    }

    /// Gaussian-like blur made of several box blurs. `sigma` is in bitmap pixels.
    static func blurred(_ image: PixelImage, sigma: Double, passes: Int, clampEdges: Bool) -> PixelImage {
        guard sigma >= 0.3, !image.isEmpty else { return image }
        var result = image
        for radius in boxRadii(sigma: sigma, passes: passes) {
            result.pixels = boxPass(result.pixels, width: image.width, height: image.height,
                                    radius: radius, horizontal: true, clampEdges: clampEdges)
            result.pixels = boxPass(result.pixels, width: image.width, height: image.height,
                                    radius: radius, horizontal: false, clampEdges: clampEdges)
        }
        return result
    }

    // MARK: - 5. Gaussian Blur

    private static func gaussianBlur(_ image: PixelImage, _ v: EffectValues, _ scale: Double) -> PixelImage {
        let sigma = v.scalar("radius") * scale
        if sigma < 0.3 { return image }                       // no blur: nothing to do
        let passes = [2, 3, 4][min(max(v.choice("quality"), 0), 2)]
        let repeatEdges = v.choice("edges") != 0
        return blurred(image, sigma: sigma, passes: passes, clampEdges: repeatEdges)
    }

    // MARK: - 6. Sharpen

    /// Unsharp mask: add back the difference between the picture and a blurred copy. Each result is limited to
    /// slightly beyond the range of its 3 x 3 neighbours, which stops the bright and dark halos that plain
    /// unsharp masking draws around edges.
    private static func sharpen(_ image: PixelImage, _ v: EffectValues, _ scale: Double) -> PixelImage {
        let amount = Float(v.scalar("amount"))
        if amount <= 0 || image.isEmpty { return image }
        let blur = blurred(image, sigma: v.scalar("radius") * scale, passes: 3, clampEdges: true)
        var result = image
        let w = image.width, h = image.height
        for y in 0..<h {
            for x in 0..<w {
                let o = image.offset(x, y)
                let alpha = image.pixels[o + 3]
                if alpha <= 0 { continue }
                for channel in 0..<3 {
                    var low = Float.greatestFiniteMagnitude
                    var high = -Float.greatestFiniteMagnitude
                    for ny in max(0, y - 1)...min(h - 1, y + 1) {
                        for nx in max(0, x - 1)...min(w - 1, x + 1) {
                            let value = image.pixels[image.offset(nx, ny) + channel]
                            low = min(low, value)
                            high = max(high, value)
                        }
                    }
                    let range = high - low
                    let original = image.pixels[o + channel]
                    let sharpened = original + amount * (original - blur.pixels[o + channel])
                    let limited = min(max(sharpened, low - 0.15 * range), high + 0.15 * range)
                    result.pixels[o + channel] = min(max(limited, 0), alpha)
                }
            }
        }
        return result
    }

    // MARK: - 7. Vignette

    /// Darkens (positive intensity) or lightens (negative) toward the edges. Distance is measured from the centre
    /// point, scaled so the corners of a centred vignette are at 1.
    private static func vignette(_ image: PixelImage, _ v: EffectValues, _ scale: Double) -> PixelImage {
        let intensity = v.scalar("intensity")
        if intensity == 0 || image.isEmpty { return image }
        let radius = v.scalar("radius")
        let softness = v.scalar("softness")
        let centre = v.vector("center")
        let w = image.width, h = image.height
        let cx = centre.x * Double(w), cy = centre.y * Double(h)
        let halfWidth = max(Double(w) / 2, 1), halfHeight = max(Double(h) / 2, 1)
        let edge0 = radius * (1 - softness), edge1 = radius * (1 + softness)
        var result = image
        for y in 0..<h {
            for x in 0..<w {
                let dx = (Double(x) + 0.5 - cx) / halfWidth
                let dy = (Double(y) + 0.5 - cy) / halfHeight
                let distance = (dx * dx + dy * dy).squareRoot() / 2.0.squareRoot()
                let factor = edge1 <= edge0 ? (distance >= edge0 ? 1.0 : 0.0) : smoothstep(edge0, edge1, distance)
                let amount = Float(intensity * factor)
                if amount == 0 { continue }
                let p = image.pixel(x, y)
                if amount > 0 {
                    result.setPixel(x, y, r: p.r * (1 - amount), g: p.g * (1 - amount), b: p.b * (1 - amount), a: p.a)
                } else {
                    let lift = -amount
                    result.setPixel(x, y, r: p.r + (p.a - p.r) * lift, g: p.g + (p.a - p.g) * lift,
                                    b: p.b + (p.a - p.b) * lift, a: p.a)
                }
            }
        }
        return result
    }

    // MARK: - Shadow and glow building blocks

    private static func alphaPlane(_ image: PixelImage) -> [Float] {
        (0..<(image.width * image.height)).map { image.pixels[$0 * 4 + 3] }
    }

    /// Spreads a plane outward: every pixel takes the largest value within `radius` pixels (a square).
    private static func dilated(_ plane: [Float], width: Int, height: Int, radius: Int) -> [Float] {
        if radius <= 0 { return plane }
        var horizontal = plane
        for y in 0..<height {
            for x in 0..<width {
                var best: Float = 0
                for nx in max(0, x - radius)...min(width - 1, x + radius) {
                    best = max(best, plane[y * width + nx])
                }
                horizontal[y * width + x] = best
            }
        }
        var result = horizontal
        for y in 0..<height {
            for x in 0..<width {
                var best: Float = 0
                for ny in max(0, y - radius)...min(height - 1, y + radius) {
                    best = max(best, horizontal[ny * width + x])
                }
                result[y * width + x] = best
            }
        }
        return result
    }

    /// Blurs a single plane by putting it in the alpha channel of a picture.
    private static func blurredPlane(_ plane: [Float], width: Int, height: Int, sigma: Double) -> [Float] {
        guard sigma >= 0.3 else { return plane }
        var carrier = PixelImage(width: width, height: height)
        for i in 0..<(width * height) { carrier.pixels[i * 4 + 3] = plane[i] }
        let result = blurred(carrier, sigma: sigma, passes: 3, clampEdges: false)
        return alphaPlane(result)
    }

    // MARK: - 8. Drop Shadow

    /// A soft copy of the layer's own shape (its alpha) is put behind it, shifted by distance and angle.
    /// The canvas grows so the shadow is not cut off. A transparent area casts no shadow.
    private static func dropShadow(_ image: PixelImage, _ v: EffectValues, _ scale: Double) -> PixelImage {
        let opacity = Float(v.scalar("opacity"))
        if opacity <= 0 || image.isEmpty { return image }
        let sigma = v.scalar("blur") * scale
        let distance = v.scalar("distance") * scale
        let angle = v.scalar("angle") * Double.pi / 180
        let spread = Int((v.scalar("spread") * scale).rounded())
        let dx = Int((cos(angle) * distance).rounded())
        let dy = Int((sin(angle) * distance).rounded())
        let margin = min(Int((distance + 3 * sigma).rounded(.up)) + spread + 2, maximumMargin)

        let canvas = image.padded(by: margin)
        let w = canvas.width, h = canvas.height
        var shape = dilated(alphaPlane(canvas), width: w, height: h, radius: spread)
        shape = blurredPlane(shape, width: w, height: h, sigma: sigma)
        let colour = v.color("shadow")

        var result = canvas
        for y in 0..<h {
            for x in 0..<w {
                let sx = x - dx, sy = y - dy
                guard sx >= 0, sx < w, sy >= 0, sy < h else { continue }
                let shadowAlpha = shape[sy * w + sx] * opacity
                if shadowAlpha <= 0 { continue }
                let p = canvas.pixel(x, y)
                let behind = 1 - p.a
                result.setPixel(x, y,
                                r: p.r + colour.0 * shadowAlpha * behind,
                                g: p.g + colour.1 * shadowAlpha * behind,
                                b: p.b + colour.2 * shadowAlpha * behind,
                                a: p.a + shadowAlpha * behind)
            }
        }
        return result
    }

    // MARK: - 9. Glow

    /// The bright parts of the picture (by luminance, weighted by alpha) are blurred, tinted and added back as light.
    private static func glow(_ image: PixelImage, _ v: EffectValues, _ scale: Double) -> PixelImage {
        let intensity = Float(v.scalar("intensity"))
        if intensity <= 0 || image.isEmpty { return image }
        let sigma = v.scalar("radius") * scale
        let threshold = Float(min(v.scalar("threshold"), 0.99))
        let margin = min(Int((3 * sigma).rounded(.up)) + 2, maximumMargin)
        let canvas = image.padded(by: margin)
        let w = canvas.width, h = canvas.height

        var bright = [Float](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            let o = i * 4
            let light = luma(canvas.pixels[o], canvas.pixels[o + 1], canvas.pixels[o + 2])   // already weighted by alpha
            bright[i] = max(0, (light - threshold) / (1 - threshold))
        }
        let spread = blurredPlane(bright, width: w, height: h, sigma: sigma)
        let colour = v.color("color")
        let glowOnly = v.choice("mode") == 1

        var result = canvas
        for i in 0..<(w * h) {
            let o = i * 4
            let light = min(spread[i] * intensity, 1)
            if light <= 0 && !glowOnly { continue }
            let glowRed = colour.0 * light, glowGreen = colour.1 * light, glowBlue = colour.2 * light
            if glowOnly {
                result.pixels[o] = glowRed
                result.pixels[o + 1] = glowGreen
                result.pixels[o + 2] = glowBlue
                result.pixels[o + 3] = light
            } else {
                let sourceAlpha = canvas.pixels[o + 3]
                let alpha = sourceAlpha + light * (1 - sourceAlpha)
                result.pixels[o] = min(canvas.pixels[o] + glowRed, alpha)
                result.pixels[o + 1] = min(canvas.pixels[o + 1] + glowGreen, alpha)
                result.pixels[o + 2] = min(canvas.pixels[o + 2] + glowBlue, alpha)
                result.pixels[o + 3] = alpha
            }
        }
        return result
    }

    // MARK: - 10. Gradient Map

    /// Replaces each colour by a colour from a three-stop gradient (shadows, midtones, highlights),
    /// chosen by how bright the original was. Alpha is kept.
    private static func gradientMap(_ image: PixelImage, _ v: EffectValues, _ scale: Double) -> PixelImage {
        let low = v.color("low"), middle = v.color("mid"), high = v.color("high")
        let middlePosition = Float(v.scalar("midPosition"))
        let mix = Float(v.scalar("mix"))
        if mix <= 0 { return image }
        func lerp(_ a: (Float, Float, Float), _ b: (Float, Float, Float), _ t: Float) -> (Float, Float, Float) {
            (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t)
        }
        return image.mapColors { r, g, b in
            let brightness = min(max(luma(r, g, b), 0), 1)
            let target: (Float, Float, Float)
            if brightness <= middlePosition {
                target = lerp(low, middle, middlePosition > 0 ? brightness / middlePosition : 1)
            } else {
                target = lerp(middle, high, (brightness - middlePosition) / (1 - middlePosition))
            }
            return (r + (target.0 - r) * mix, g + (target.1 - g) * mix, b + (target.2 - b) * mix)
        }
    }

    // MARK: - 11. RGB Split

    /// Red and blue are sampled from shifted positions, green stays put. Edges repeat, so there are no transparent borders.
    private static func rgbSplit(_ image: PixelImage, _ v: EffectValues, _ scale: Double) -> PixelImage {
        let intensity = Float(v.scalar("intensity"))
        let red = v.vector("redOffset"), blue = v.vector("blueOffset")
        if intensity <= 0 || (red == .zero && blue == .zero) || image.isEmpty { return image }
        var result = image
        for y in 0..<image.height {
            for x in 0..<image.width {
                let px = Double(x) + 0.5, py = Double(y) + 0.5
                let r = image.sample(x: px - red.x * scale, y: py - red.y * scale)
                let b = image.sample(x: px - blue.x * scale, y: py - blue.y * scale)
                let original = image.pixel(x, y)
                let alpha = max(r.a, original.a, b.a)
                let nr = min(r.r, alpha), ng = min(original.g, alpha), nb = min(b.b, alpha)
                result.setPixel(x, y,
                                r: original.r + (nr - original.r) * intensity,
                                g: original.g + (ng - original.g) * intensity,
                                b: original.b + (nb - original.b) * intensity,
                                a: original.a + (alpha - original.a) * intensity)
            }
        }
        return result
    }

    // MARK: - 12. Pixelate

    /// Each square block becomes the average of the pixels inside it (alpha is averaged too).
    private static func pixelate(_ image: PixelImage, _ v: EffectValues, _ scale: Double) -> PixelImage {
        let block = Int((v.scalar("blockSize") * scale).rounded())
        if block <= 1 || image.isEmpty { return image }
        var result = image
        for top in stride(from: 0, to: image.height, by: block) {
            let bottom = min(top + block, image.height)
            for left in stride(from: 0, to: image.width, by: block) {
                let right = min(left + block, image.width)
                var sums = [Float](repeating: 0, count: 4)
                for y in top..<bottom {
                    for x in left..<right {
                        let p = image.pixel(x, y)
                        sums[0] += p.r; sums[1] += p.g; sums[2] += p.b; sums[3] += p.a
                    }
                }
                let count = Float((bottom - top) * (right - left))
                for y in top..<bottom {
                    for x in left..<right {
                        result.setPixel(x, y, r: sums[0] / count, g: sums[1] / count, b: sums[2] / count, a: sums[3] / count)
                    }
                }
            }
        }
        return result
    }

    // MARK: - 13. Posterize

    /// Each channel is cut into `levels` equal steps and snapped to evenly spaced values from 0 to 1.
    private static func posterize(_ image: PixelImage, _ v: EffectValues, _ scale: Double) -> PixelImage {
        let levels = Float(min(max(Int(v.scalar("levels").rounded()), 2), 255))
        func step(_ c: Float) -> Float { min((c * levels).rounded(.down), levels - 1) / (levels - 1) }
        return image.mapColors { r, g, b in (step(r), step(g), step(b)) }
    }

    // MARK: - 14. Directional Blur

    /// Averages samples along a line at the given angle, centred on each pixel. Edges repeat.
    private static func directionalBlur(_ image: PixelImage, _ v: EffectValues, _ scale: Double) -> PixelImage {
        let distance = v.scalar("distance") * scale
        if distance < 0.5 || image.isEmpty { return image }
        let angle = v.scalar("angle") * Double.pi / 180
        let dx = cos(angle), dy = sin(angle)
        let steps = min(max(Int(distance.rounded()), 1), 48)
        var result = image
        for y in 0..<image.height {
            for x in 0..<image.width {
                let px = Double(x) + 0.5, py = Double(y) + 0.5
                var r: Float = 0, g: Float = 0, b: Float = 0, a: Float = 0
                for i in 0...steps {
                    let t = -distance / 2 + distance * Double(i) / Double(steps)
                    let s = image.sample(x: px + dx * t, y: py + dy * t)
                    r += s.r; g += s.g; b += s.b; a += s.a
                }
                let count = Float(steps + 1)
                result.setPixel(x, y, r: r / count, g: g / count, b: b / count, a: a / count)
            }
        }
        return result
    }

    // MARK: - 15. Wave Warp

    private static func waveValue(_ degrees: Double, type: Int) -> Double {
        let radians = degrees * Double.pi / 180
        switch type {
        case 1: return 2 / Double.pi * asin(sin(radians))     // triangle
        case 2: return sin(radians) >= 0 ? 1 : -1               // square
        default: return sin(radians)                            // sine
        }
    }

    /// Pixels are pushed sideways by a wave. `direction` is the direction of the push; the wave itself runs
    /// across it. `frequency` is the number of waves in 1000 layer pixels. Edges repeat.
    private static func waveWarp(_ image: PixelImage, _ v: EffectValues, _ scale: Double) -> PixelImage {
        let amplitude = v.scalar("amplitude") * scale
        let frequency = v.scalar("frequency")
        if amplitude < 0.01 || frequency <= 0 || image.isEmpty { return image }
        let wavelength = max(1000 / frequency, 1) * scale
        let phase = v.scalar("phase")
        let direction = v.scalar("direction") * Double.pi / 180
        let type = v.choice("waveType")
        let pushX = cos(direction), pushY = sin(direction)
        let acrossX = -sin(direction), acrossY = cos(direction)
        var result = image
        for y in 0..<image.height {
            for x in 0..<image.width {
                let px = Double(x) + 0.5, py = Double(y) + 0.5
                let along = px * acrossX + py * acrossY
                let wave = waveValue(along / wavelength * 360 + phase, type: type)
                let s = image.sample(x: px - amplitude * wave * pushX, y: py - amplitude * wave * pushY)
                result.setPixel(x, y, r: s.r, g: s.g, b: s.b, a: s.a)
            }
        }
        return result
    }

    // MARK: - 16. Chroma Key

    /// Removes pixels close to a selected key colour. Alpha remains premultiplied correctly.
    private static func chromaKey(_ image: PixelImage, _ v: EffectValues, _ scale: Double) -> PixelImage {
        guard !image.isEmpty else { return image }
        let kr = Float(v.scalar("keyRed")), kg = Float(v.scalar("keyGreen")), kb = Float(v.scalar("keyBlue"))
        let tolerance = Float(v.scalar("tolerance")) * 1.732
        let softness = max(Float(v.scalar("edgeSoftness")) * 1.732, 0.0001)
        let spill = Float(v.scalar("spillSuppression"))
        var result = image
        for y in 0..<image.height {
            for x in 0..<image.width {
                let p = image.straight(x, y)
                guard p.a > 0 else { continue }
                let dr = p.r - kr, dg = p.g - kg, db = p.b - kb
                let distance = (dr * dr + dg * dg + db * db).squareRoot()
                let t = min(max((distance - tolerance) / softness, 0), 1)
                let keep = t * t * (3 - 2 * t)
                let r = p.r, b = p.b
                var g = p.g
                if spill > 0 {
                    let keyDominance = max(0, (kg - max(kr, kb)) - (g - max(r, b)))
                    let suppression = min(max(keyDominance * spill, 0), 1)
                    g = max(0, g - suppression)
                }
                result.setStraight(x, y, r: r, g: g, b: b, a: p.a * keep)
            }
        }
        return result
    }

    // MARK: - 17. Box Blur

    private static func boxBlur(_ image: PixelImage, _ v: EffectValues, _ scale: Double) -> PixelImage {
        let radius = v.scalar("radius") * scale
        guard radius >= 0.5 else { return image }
        // One horizontal and one vertical running-average pass is a true square-kernel box blur.
        var result = image
        let r = min(max(Int(radius.rounded()), 1), 100)
        let transparentEdges = v.choice("edgeMode") == 1
        result.pixels = boxPass(result.pixels, width: result.width, height: result.height,
                                radius: r, horizontal: true, clampEdges: !transparentEdges)
        result.pixels = boxPass(result.pixels, width: result.width, height: result.height,
                                radius: r, horizontal: false, clampEdges: !transparentEdges)
        return result
    }

    // MARK: - 18. Zoom Blur

    private static func zoomBlur(_ image: PixelImage, _ v: EffectValues, _ scale: Double) -> PixelImage {
        let amount = v.scalar("amount") * scale
        guard amount >= 0.5, !image.isEmpty else { return image }
        let centre = v.vector("center")
        let cx = centre.x * Double(image.width), cy = centre.y * Double(image.height)
        let steps = min(max(Int(amount / 3), 4), 32)
        var result = image
        for y in 0..<image.height {
            for x in 0..<image.width {
                let px = Double(x) + 0.5, py = Double(y) + 0.5
                var r: Float = 0, g: Float = 0, b: Float = 0, a: Float = 0
                for i in 0...steps {
                    let t = Double(i) / Double(steps) - 0.5
                    let factor = 1 + t * amount / max(Double(max(image.width, image.height)), 1)
                    let sx = cx + (px - cx) * factor
                    let sy = cy + (py - cy) * factor
                    let sample = image.sample(x: sx, y: sy)
                    r += sample.r; g += sample.g; b += sample.b; a += sample.a
                }
                let count = Float(steps + 1)
                result.setPixel(x, y, r: r / count, g: g / count, b: b / count, a: a / count)
            }
        }
        return result
    }

    // MARK: - 19. Noise

    /// Deterministic per-pixel noise: the same settings render identically on every preview refresh.
    private static func noise(_ image: PixelImage, _ v: EffectValues, _ scale: Double) -> PixelImage {
        let amount = Float(v.scalar("amount"))
        guard amount > 0, !image.isEmpty else { return image }
        let monochrome = v.choice("monochrome") == 1
        let seed = UInt64(max(0, v.scalar("seed").rounded()))
        var result = image
        func hash(_ x: Int, _ y: Int, _ channel: UInt64) -> Float {
            var n = UInt64(bitPattern: Int64(x)) &* 0x9E3779B185EBCA87
            n ^= UInt64(bitPattern: Int64(y)) &* 0xC2B2AE3D27D4EB4F
            n ^= seed &* 0x165667B19E3779F9 &+ channel
            n ^= n >> 30; n &*= 0xBF58476D1CE4E5B9
            n ^= n >> 27; n &*= 0x94D049BB133111EB
            n ^= n >> 31
            return Float(Double(n & 0xFFFFFF) / Double(0xFFFFFF)) * 2 - 1
        }
        for y in 0..<image.height {
            for x in 0..<image.width {
                let p = image.straight(x, y)
                guard p.a > 0 else { continue }
                let nr = hash(x, y, 0) * amount
                let ng = monochrome ? nr : hash(x, y, 1) * amount
                let nb = monochrome ? nr : hash(x, y, 2) * amount
                result.setStraight(x, y, r: min(max(p.r + nr, 0), 1),
                                   g: min(max(p.g + ng, 0), 1),
                                   b: min(max(p.b + nb, 0), 1), a: p.a)
            }
        }
        return result
    }

    // MARK: - 20. Halftone Dots

    /// A monochrome screen of variable-sized dots, useful as a stylised print effect.
    private static func halftoneDots(_ image: PixelImage, _ v: EffectValues, _ scale: Double) -> PixelImage {
        guard !image.isEmpty else { return image }
        let cell = max(2, min(Int((v.scalar("dotSize") * scale).rounded()), 120))
        let contrast = Float(v.scalar("contrast"))
        let angle = v.scalar("angle") * Double.pi / 180
        let ca = cos(angle), sa = sin(angle)
        var result = image
        for y in 0..<image.height {
            for x in 0..<image.width {
                let p = image.straight(x, y)
                guard p.a > 0 else { continue }
                let rx = Double(x) * ca - Double(y) * sa
                let ry = Double(x) * sa + Double(y) * ca
                let fx = (rx / Double(cell)).truncatingRemainder(dividingBy: 1) - 0.5
                let fy = (ry / Double(cell)).truncatingRemainder(dividingBy: 1) - 0.5
                let luminance = Double(min(max(luma(p.r, p.g, p.b), 0), 1))
                let radius = (1 - luminance) * Double(contrast) * 0.7
                let inside = (fx * fx + fy * fy).squareRoot() < radius
                let value: Float = inside ? 0 : 1
                result.setStraight(x, y, r: p.r * value, g: p.g * value, b: p.b * value, a: p.a)
            }
        }
        return result
    }


    // MARK: - 21. Roughen Edges

    /// Adds deterministic irregularity to partially transparent edge pixels without changing solid interiors.
    private static func roughenEdges(_ image: PixelImage, _ v: EffectValues, _ scale: Double) -> PixelImage {
        guard !image.isEmpty else { return image }
        let amount = Float(v.scalar("amount"))
        let detail = max(1, Int((v.scalar("scale") * scale).rounded()))
        let softness = Float(v.scalar("softness"))
        guard amount > 0 else { return image }
        var result = image
        func hash(_ x: Int, _ y: Int) -> Float {
            var n = UInt64(bitPattern: Int64(x / detail)) &* 0x9E3779B185EBCA87
            n ^= UInt64(bitPattern: Int64(y / detail)) &* 0xC2B2AE3D27D4EB4F
            n ^= 0x165667B19E3779F9
            n ^= n >> 30; n &*= 0xBF58476D1CE4E5B9
            n ^= n >> 27; n &*= 0x94D049BB133111EB
            n ^= n >> 31
            return Float(Double(n & 0xFFFFFF) / Double(0xFFFFFF)) * 2 - 1
        }
        for y in 0..<image.height {
            for x in 0..<image.width {
                let p = image.straight(x, y)
                var low: Float = 1, high: Float = 0
                for ny in max(0, y - 1)...min(image.height - 1, y + 1) {
                    for nx in max(0, x - 1)...min(image.width - 1, x + 1) {
                        let alpha = image.pixel(nx, ny).a
                        low = min(low, alpha); high = max(high, alpha)
                    }
                }
                let edgeRange = high - low
                guard edgeRange > 0.001 else { continue }
                let jitter = hash(x, y) * amount * edgeRange
                let nextAlpha = min(max(p.a + jitter, 0), 1)
                // Softness reduces the displacement near the very faint fringe.
                let mix = min(max(edgeRange * (1 - softness) + softness, 0), 1)
                let alpha = p.a + (nextAlpha - p.a) * mix
                result.setStraight(x, y, r: p.r, g: p.g, b: p.b, a: alpha)
            }
        }
        return result
    }

    // MARK: - 22. Random Displacement

    /// A deterministic procedural displacement field. This is not a separate-source-map displacement effect.
    private static func randomDisplacement(_ image: PixelImage, _ v: EffectValues, _ scale: Double) -> PixelImage {
        guard !image.isEmpty else { return image }
        let dx = v.scalar("horizontal") * scale
        let dy = v.scalar("vertical") * scale
        let cell = max(1, Int((v.scalar("scale") * scale).rounded()))
        let seed = UInt64(max(0, v.scalar("seed").rounded()))
        guard dx >= 0.5 || dy >= 0.5 else { return image }
        func hash(_ x: Int, _ y: Int, _ channel: UInt64) -> Double {
            var n = UInt64(bitPattern: Int64(x / cell)) &* 0x9E3779B185EBCA87
            n ^= UInt64(bitPattern: Int64(y / cell)) &* 0xC2B2AE3D27D4EB4F
            n ^= seed &* 0x165667B19E3779F9 &+ channel
            n ^= n >> 30; n &*= 0xBF58476D1CE4E5B9
            n ^= n >> 27; n &*= 0x94D049BB133111EB
            n ^= n >> 31
            return Double(n & 0xFFFFFF) / Double(0xFFFFFF) * 2 - 1
        }
        var result = image
        for y in 0..<image.height {
            for x in 0..<image.width {
                let px = Double(x) + 0.5, py = Double(y) + 0.5
                let sample = image.sample(x: px + hash(x, y, 0) * dx,
                                          y: py + hash(x, y, 1) * dy)
                result.setPixel(x, y, r: sample.r, g: sample.g, b: sample.b, a: sample.a)
            }
        }
        return result
    }


    // MARK: - Additional colour and geometry effects

    /// Warmth moves energy toward red/yellow; coolness moves it toward blue. Alpha is preserved.
    private static func colorTemperature(_ image: PixelImage, _ v: EffectValues, _ scale: Double) -> PixelImage {
        let temperature = Float(v.scalar("temperature"))
        if temperature == 0 { return image }
        return image.mapColors { r, g, b in
            let warm = temperature * 0.22
            return (r + warm, g + warm * 0.12, b - warm)
        }
    }

    /// Mixes each pixel with a colour tint modulated by its luminance.
    private static func colorize(_ image: PixelImage, _ v: EffectValues, _ scale: Double) -> PixelImage {
        let tint = v.color("tint")
        let amount = Float(v.scalar("amount"))
        if amount <= 0 { return image }
        return image.mapColors { r, g, b in
            let grey = luma(r, g, b)
            let tr = tint.0 * grey, tg = tint.1 * grey, tb = tint.2 * grey
            return (r + (tr - r) * amount, g + (tg - g) * amount, b + (tb - b) * amount)
        }
    }

    /// Exposure is measured in stops; gamma is applied after exposure in linear RGB values.
    private static func exposureGamma(_ image: PixelImage, _ v: EffectValues, _ scale: Double) -> PixelImage {
        let exposure = v.scalar("exposure")
        let gamma = max(0.1, v.scalar("gamma"))
        if exposure == 0 && gamma == 1 { return image }
        let factor = Float(pow(2, exposure))
        let inverseGamma = Float(1 / gamma)
        return image.mapColors { r, g, b in
            (pow(max(0, r * factor), inverseGamma),
             pow(max(0, g * factor), inverseGamma),
             pow(max(0, b * factor), inverseGamma))
        }
    }

    /// Sobel edge detector. It emits a grayscale edge map while retaining the original alpha.
    private static func findEdges(_ image: PixelImage, _ v: EffectValues, _ scale: Double) -> PixelImage {
        guard !image.isEmpty else { return image }
        let strength = Float(v.scalar("strength"))
        var result = image
        func grey(_ x: Int, _ y: Int) -> Float {
            let px = image.straight(min(max(x, 0), image.width - 1), min(max(y, 0), image.height - 1))
            return luma(px.r, px.g, px.b)
        }
        for y in 0..<image.height {
            for x in 0..<image.width {
                let gx = -grey(x - 1, y - 1) + grey(x + 1, y - 1)
                    - 2 * grey(x - 1, y) + 2 * grey(x + 1, y)
                    - grey(x - 1, y + 1) + grey(x + 1, y + 1)
                let gy = -grey(x - 1, y - 1) - 2 * grey(x, y - 1) - grey(x + 1, y - 1)
                    + grey(x - 1, y + 1) + 2 * grey(x, y + 1) + grey(x + 1, y + 1)
                let edge = min(1, sqrt(gx * gx + gy * gy) * strength)
                let alpha = image.straight(x, y).a
                result.setStraight(x, y, r: edge, g: edge, b: edge, a: alpha)
            }
        }
        return result
    }

    /// Flips the full image horizontally or vertically without changing its bounds.
    private static func flipLayer(_ image: PixelImage, _ v: EffectValues, _ scale: Double) -> PixelImage {
        guard !image.isEmpty else { return image }
        var result = image
        let vertical = v.choice("axis") == 1
        for y in 0..<image.height {
            for x in 0..<image.width {
                let sx = vertical ? x : image.width - 1 - x
                let sy = vertical ? image.height - 1 - y : y
                let p = image.pixel(sx, sy)
                result.setPixel(x, y, r: p.r, g: p.g, b: p.b, a: p.a)
            }
        }
        return result
    }

    /// Mirrors the left/top half across the centre line, producing a seamless symmetric reflection.
    private static func mirror(_ image: PixelImage, _ v: EffectValues, _ scale: Double) -> PixelImage {
        guard !image.isEmpty else { return image }
        var result = image
        let vertical = v.choice("axis") == 1
        for y in 0..<image.height {
            for x in 0..<image.width {
                let sx = vertical ? x : min(x, image.width - 1 - x)
                let sy = vertical ? min(y, image.height - 1 - y) : y
                let p = image.pixel(sx, sy)
                result.setPixel(x, y, r: p.r, g: p.g, b: p.b, a: p.a)
            }
        }
        return result
    }

    // MARK: - Additional effects requested for the mobile editor

    /// A performant approximation of lens blur. This is a soft blur, not a physically modelled iris/bokeh kernel.
    private static func lensBlur(_ image: PixelImage, _ v: EffectValues, _ scale: Double) -> PixelImage {
        let radius = min(max(v.scalar("radius") * scale, 0), 80 * scale)
        guard radius >= 0.5 else { return image }
        let blurredImage = blurred(image, sigma: radius, passes: 3, clampEdges: true)
        let bokeh = Float(min(max(v.scalar("bokeh"), 0), 1))
        guard bokeh > 0 else { return blurredImage }
        // A subtle highlight lift approximates bright bokeh discs without pretending to simulate a lens aperture.
        return blurredImage.mapColors { r, g, b in
            let highlight = max(0, luma(r, g, b) - 0.72) * bokeh * 0.35
            return (r + highlight, g + highlight, b + highlight)
        }
    }

    private static func threshold(_ image: PixelImage, _ v: EffectValues, _ scale: Double) -> PixelImage {
        let level = Float(min(max(v.scalar("level"), 0), 1))
        let alphaMatte = v.choice("mode") == 1
        var result = image
        for y in 0..<image.height {
            for x in 0..<image.width {
                let p = image.straight(x, y)
                let white: Float = luma(p.r, p.g, p.b) >= level ? 1 : 0
                if alphaMatte {
                    result.setStraight(x, y, r: p.r, g: p.g, b: p.b, a: p.a * white)
                } else {
                    result.setStraight(x, y, r: white, g: white, b: white, a: p.a)
                }
            }
        }
        return result
    }

    private static func lumaFade(_ image: PixelImage, _ v: EffectValues, _ scale: Double) -> PixelImage {
        let threshold = Float(min(max(v.scalar("threshold"), 0), 1))
        let softness = Float(max(0.001, v.scalar("softness")))
        let revealDark = v.choice("direction") == 1
        var result = image
        for y in 0..<image.height {
            for x in 0..<image.width {
                let p = image.straight(x, y)
                var t = min(max((luma(p.r, p.g, p.b) - (threshold - softness / 2)) / softness, 0), 1)
                if revealDark { t = 1 - t }
                // A luma matte that can be animated by keyframing the threshold.
                result.setStraight(x, y, r: p.r, g: p.g, b: p.b, a: p.a * t)
            }
        }
        return result
    }

    private static func vhs(_ image: PixelImage, _ v: EffectValues, _ scale: Double) -> PixelImage {
        guard !image.isEmpty else { return image }
        let intensity = Float(min(max(v.scalar("intensity"), 0), 1))
        let tracking = v.scalar("tracking") * scale
        let scanlines = Float(min(max(v.scalar("scanlines"), 0), 1))
        let chromaLoss = Float(min(max(v.scalar("chromaLoss"), 0), 1))
        let noiseAmount = Float(min(max(v.scalar("noise"), 0), 1))
        let tapeMode = v.choice("tapeMode")
        let modeNoise: Float = [1.0, 1.45, 2.0][min(max(tapeMode, 0), 2)]
        let modeChroma: Float = [1.0, 0.78, 0.55][min(max(tapeMode, 0), 2)]
        var result = image
        for y in 0..<image.height {
            let band = (y % 47 == 0) ? tracking * 2 : ((y % 19 == 0) ? tracking * 0.35 : 0)
            let scanFactor: Float = y.isMultiple(of: 2) ? 1 - scanlines * 0.32 : 1
            for x in 0..<image.width {
                let p = image.straight(x, y)
                let shift = Double(intensity) * (1.5 + Double(tapeMode) * 0.7)
                let red = image.sample(x: Double(x) + 0.5 + shift + band, y: Double(y) + 0.5)
                let blue = image.sample(x: Double(x) + 0.5 - shift - band, y: Double(y) + 0.5)
                let grey = luma(p.r, p.g, p.b)
                let chroma = max(0, 1 - chromaLoss * modeChroma)
                // Deterministic grain keeps previews repeatable; the Metal path animates its seed per frame.
                let hash = UInt32(truncatingIfNeeded: x &* 374761393 ^ y &* 668265263 ^ (tapeMode + 1) &* 2246822519)
                let mixed = (hash ^ (hash >> 13)) &* 1274126177
                let grain = (Float(mixed & 0xFFFF) / 32767.5 - 1) * noiseAmount * modeNoise * intensity * 0.12
                let warmth = Float(intensity * 0.035)
                let r = (grey + (min(1, red.r + warmth) - grey) * chroma + grain) * scanFactor
                let g = (grey + (p.g - grey) * chroma + grain * 0.72) * scanFactor
                let b = (grey + (min(1, blue.b + intensity * 0.015) - grey) * chroma + grain * 0.9) * scanFactor
                result.setStraight(x, y, r: min(1, max(0, r)), g: min(1, max(0, g)), b: min(1, max(0, b)), a: p.a)
            }
        }
        return result
    }

    private static func pixelSort(_ image: PixelImage, _ v: EffectValues, _ scale: Double) -> PixelImage {
        guard !image.isEmpty else { return image }
        let threshold = Float(min(max(v.scalar("threshold"), 0), 1))
        let runLength = max(2, min(Int((v.scalar("length") * scale).rounded()), 160))
        let vertical = v.choice("direction") == 1
        var result = image
        let major = vertical ? image.width : image.height
        let minor = vertical ? image.height : image.width
        for line in 0..<minor {
            var start = 0
            while start < major {
                let x = vertical ? line : start
                let y = vertical ? start : line
                if luma(image.straight(x, y).r, image.straight(x, y).g, image.straight(x, y).b) < threshold {
                    start += 1; continue
                }
                var end = start
                while end < major && end - start < runLength {
                    let px = vertical ? line : end
                    let py = vertical ? end : line
                    let c = image.straight(px, py)
                    if luma(c.r, c.g, c.b) < threshold { break }
                    end += 1
                }
                if end - start > 1 {
                    let sorted = (start..<end).map { i -> (Float, (r: Float, g: Float, b: Float, a: Float)) in
                        let px = vertical ? line : i, py = vertical ? i : line
                        let c = image.straight(px, py)
                        return (luma(c.r, c.g, c.b), c)
                    }.sorted { $0.0 < $1.0 }
                    for (offset, item) in sorted.enumerated() {
                        let px = vertical ? line : start + offset
                        let py = vertical ? start + offset : line
                        result.setStraight(px, py, r: item.1.r, g: item.1.g, b: item.1.b, a: item.1.a)
                    }
                }
                start = max(end, start + 1)
            }
        }
        return result
    }

    private static func rgbBlur(_ image: PixelImage, _ v: EffectValues, _ scale: Double) -> PixelImage {
        guard !image.isEmpty else { return image }
        let angle = v.scalar("angle") * Double.pi / 180
        let dx = cos(angle), dy = sin(angle)
        let redOffset = v.scalar("redOffset") * scale
        let greenOffset = v.scalar("greenOffset") * scale
        let blueOffset = v.scalar("blueOffset") * scale
        var result = image
        for y in 0..<image.height {
            for x in 0..<image.width {
                let px = Double(x) + 0.5, py = Double(y) + 0.5
                let r = image.sample(x: px + dx * redOffset, y: py + dy * redOffset)
                let g = image.sample(x: px + dx * greenOffset, y: py + dy * greenOffset)
                let b = image.sample(x: px + dx * blueOffset, y: py + dy * blueOffset)
                let original = image.straight(x, y)
                result.setStraight(x, y, r: r.r, g: g.g, b: b.b, a: original.a)
            }
        }
        return result
    }

    private static func motionTile(_ image: PixelImage, _ v: EffectValues, _ scale: Double) -> PixelImage {
        guard !image.isEmpty else { return image }
        let factor = max(0.5, min(v.scalar("scale") / 100, 3))
        let offsetX = v.scalar("offsetX") / 100 * Double(image.width)
        let offsetY = v.scalar("offsetY") / 100 * Double(image.height)
        var result = image
        for y in 0..<image.height {
            for x in 0..<image.width {
                var sx = (Double(x) + 0.5) / factor + offsetX
                var sy = (Double(y) + 0.5) / factor + offsetY
                sx = sx.truncatingRemainder(dividingBy: Double(image.width))
                sy = sy.truncatingRemainder(dividingBy: Double(image.height))
                if sx < 0 { sx += Double(image.width) }
                if sy < 0 { sy += Double(image.height) }
                let p = image.sample(x: sx, y: sy)
                result.setPixel(x, y, r: p.r, g: p.g, b: p.b, a: p.a)
            }
        }
        return result
    }


    private static func motionBlur(_ image: PixelImage, _ v: EffectValues, _ scale: Double) -> PixelImage {
        let distance = min(120, max(0, v.scalar("shutterAngle") / 360 * 24))
        let settings = EffectValues(resolved: ResolvedEffect(
            effectID: "directional-blur",
            values: ["distance": [distance], "angle": [v.scalar("angle")]]))
        return directionalBlur(image, settings, scale)
    }

    /// Procedural fallback because this project model does not yet let an effect reference a second map layer.
    private static func displacementMap(_ image: PixelImage, _ v: EffectValues, _ scale: Double) -> PixelImage {
        guard !image.isEmpty else { return image }
        let dx = v.scalar("horizontal") * scale
        let dy = v.scalar("vertical") * scale
        let edgeMode = v.choice("edges")
        var result = image
        for y in 0..<image.height {
            for x in 0..<image.width {
                let waveX = sin(Double(y) * 0.035) * dx
                let waveY = cos(Double(x) * 0.029) * dy
                var sx = Double(x) + 0.5 + waveX
                var sy = Double(y) + 0.5 + waveY
                if edgeMode == 2 {
                    sx = sx.truncatingRemainder(dividingBy: Double(image.width))
                    sy = sy.truncatingRemainder(dividingBy: Double(image.height))
                    if sx < 0 { sx += Double(image.width) }; if sy < 0 { sy += Double(image.height) }
                } else if edgeMode == 1 {
                    sx = min(max(sx, 0.5), Double(image.width) - 0.5)
                    sy = min(max(sy, 0.5), Double(image.height) - 0.5)
                }
                let p = image.sample(x: sx, y: sy)
                result.setPixel(x, y, r: p.r, g: p.g, b: p.b, a: p.a)
            }
        }
        return result
    }


    // MARK: - Additional motion-design effects

    /// Separates red and blue channels along a chosen direction while keeping green centred.
    private static func chromaticAberration(_ image: PixelImage, _ v: EffectValues, _ scale: Double) -> PixelImage {
        let distance = v.scalar("offset") * scale
        guard distance > 0, !image.isEmpty else { return image }
        let angle = v.scalar("angle") * Double.pi / 180
        let dx = cos(angle) * distance
        let dy = sin(angle) * distance
        let intensity = Float(v.scalar("intensity"))
        guard intensity > 0 else { return image }
        var result = image
        for y in 0..<image.height {
            for x in 0..<image.width {
                let px = Double(x) + 0.5
                let py = Double(y) + 0.5
                let red = image.sample(x: px - dx, y: py - dy)
                let blue = image.sample(x: px + dx, y: py + dy)
                let source = image.pixel(x, y)
                let alpha = max(source.a, red.a, blue.a)
                let r = min(red.r, alpha)
                let g = min(source.g, alpha)
                let b = min(blue.b, alpha)
                result.setPixel(x, y,
                                r: source.r + (r - source.r) * intensity,
                                g: source.g + (g - source.g) * intensity,
                                b: source.b + (b - source.b) * intensity,
                                a: source.a + (alpha - source.a) * intensity)
            }
        }
        return result
    }

    /// Deterministic, softly grouped grain. Seeded output stays stable across preview refreshes.
    private static func filmGrain(_ image: PixelImage, _ v: EffectValues, _ scale: Double) -> PixelImage {
        let amount = Float(v.scalar("amount"))
        guard amount > 0, !image.isEmpty else { return image }
        let grainSize = max(1, min(16, Int((v.scalar("grainSize") * scale).rounded())))
        let monochrome = v.choice("monochrome") == 1
        let seed = UInt64(max(0, v.scalar("seed").rounded()))
        var result = image

        func hash(_ x: Int, _ y: Int, _ channel: UInt64) -> Float {
            var n = UInt64(bitPattern: Int64(x)) &* 0x9E3779B185EBCA87
            n ^= UInt64(bitPattern: Int64(y)) &* 0xC2B2AE3D27D4EB4F
            n ^= seed &* 0x165667B19E3779F9 &+ channel
            n ^= n >> 30; n &*= 0xBF58476D1CE4E5B9
            n ^= n >> 27; n &*= 0x94D049BB133111EB
            n ^= n >> 31
            return Float(Double(n & 0xFFFFFF) / Double(0xFFFFFF)) * 2 - 1
        }

        for y in 0..<image.height {
            for x in 0..<image.width {
                let source = image.straight(x, y)
                guard source.a > 0 else { continue }
                let gx = x / grainSize, gy = y / grainSize
                let nr = hash(gx, gy, 0) * amount
                let ng = monochrome ? nr : hash(gx, gy, 1) * amount
                let nb = monochrome ? nr : hash(gx, gy, 2) * amount
                result.setStraight(x, y,
                                   r: min(max(source.r + nr, 0), 1),
                                   g: min(max(source.g + ng, 0), 1),
                                   b: min(max(source.b + nb, 0), 1),
                                   a: source.a)
            }
        }
        return result
    }

    /// Darkens repeating horizontal bands without changing alpha, ideal for retro display treatments.
    private static func scanlines(_ image: PixelImage, _ v: EffectValues, _ scale: Double) -> PixelImage {
        let spacing = max(2, Int((v.scalar("spacing") * scale).rounded()))
        let strength = Float(v.scalar("strength"))
        guard strength > 0, !image.isEmpty else { return image }
        var result = image
        for y in 0..<image.height {
            // Smooth two-row bands avoid a harsh one-pixel flicker on small previews.
            let phase = (y + Int(v.scalar("phase").rounded())) % spacing
            let band = phase < max(1, spacing / 2)
            let factor: Float = band ? 1 - strength : 1 - strength * 0.12
            for x in 0..<image.width {
                let o = image.offset(x, y)
                result.pixels[o] = image.pixels[o] * factor
                result.pixels[o + 1] = image.pixels[o + 1] * factor
                result.pixels[o + 2] = image.pixels[o + 2] * factor
                result.pixels[o + 3] = image.pixels[o + 3]
            }
        }
        return result
    }


    private static func identity(_ image: PixelImage, _ values: EffectValues, _ scale: Double) -> PixelImage { image }

}
