import Foundation

/// The processing code for each effect. Each one takes a picture, the effect's settings and the scale
/// (bitmap pixels per layer pixel) and returns a new picture. Nothing here touches the screen.
public enum ImageEffects {
    typealias Processor = (PixelImage, EffectValues, Double) -> PixelImage

    /// The largest border (in bitmap pixels) an effect may add around a picture. It keeps memory use bounded.
    static let maximumMargin = 200

    private static let table: [String: Processor] = [
        "brightness-contrast": brightnessContrast,
        "hue-shift": hueShift,
        "saturation-vibrance": saturation,
        "invert": invert,
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
    ]

    /// True when the effect has real processing code connected.
    public static func isAvailable(_ id: String) -> Bool { table[id] != nil }

    public static var availableIDs: [String] { table.keys.sorted() }

    static func processor(for id: String) -> Processor? { table[id] }

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

}
