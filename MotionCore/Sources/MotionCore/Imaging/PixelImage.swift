import Foundation

/// A picture held as numbers, so effects can be calculated (and tested) without any screen or Apple framework.
///
/// Every pixel is four numbers from 0 to 1: red, green, blue and alpha, stored "premultiplied"
/// (red, green and blue are already multiplied by alpha, which is how Apple's graphics code stores them too).
/// Pixels are stored row by row, starting at the top-left corner.
public struct PixelImage: Equatable {
    public let width: Int
    public let height: Int
    public var pixels: [Float]
    /// Where this picture's top-left corner sits compared with the top-left corner of the original picture,
    /// in pixels. It becomes negative when an effect (a shadow, a glow) has made the canvas bigger.
    public var originX: Int
    public var originY: Int

    /// A fully transparent picture.
    public init(width: Int, height: Int, originX: Int = 0, originY: Int = 0) {
        self.width = max(0, width)
        self.height = max(0, height)
        self.pixels = [Float](repeating: 0, count: self.width * self.height * 4)
        self.originX = originX
        self.originY = originY
    }

    public init(width: Int, height: Int, pixels: [Float], originX: Int = 0, originY: Int = 0) {
        precondition(width >= 0 && height >= 0 && pixels.count == width * height * 4,
                     "pixel count must be width x height x 4")
        self.width = width
        self.height = height
        self.pixels = pixels
        self.originX = originX
        self.originY = originY
    }

    /// A picture filled with one colour. The colour is given the normal way (not premultiplied).
    public static func filled(width: Int, height: Int, r: Float, g: Float, b: Float, a: Float = 1) -> PixelImage {
        var image = PixelImage(width: width, height: height)
        for y in 0..<image.height {
            for x in 0..<image.width {
                image.setStraight(x, y, r: r, g: g, b: b, a: a)
            }
        }
        return image
    }

    public var isEmpty: Bool { width == 0 || height == 0 }

    @inline(__always)
    func offset(_ x: Int, _ y: Int) -> Int { (y * width + x) * 4 }

    /// Premultiplied pixel.
    public func pixel(_ x: Int, _ y: Int) -> (r: Float, g: Float, b: Float, a: Float) {
        let o = offset(x, y)
        return (pixels[o], pixels[o + 1], pixels[o + 2], pixels[o + 3])
    }

    public mutating func setPixel(_ x: Int, _ y: Int, r: Float, g: Float, b: Float, a: Float) {
        let o = offset(x, y)
        pixels[o] = r
        pixels[o + 1] = g
        pixels[o + 2] = b
        pixels[o + 3] = a
    }

    /// The normal (not premultiplied) colour of a pixel.
    public func straight(_ x: Int, _ y: Int) -> (r: Float, g: Float, b: Float, a: Float) {
        let p = pixel(x, y)
        guard p.a > 0 else { return (0, 0, 0, 0) }
        return (p.r / p.a, p.g / p.a, p.b / p.a, p.a)
    }

    public mutating func setStraight(_ x: Int, _ y: Int, r: Float, g: Float, b: Float, a: Float) {
        setPixel(x, y, r: r * a, g: g * a, b: b * a, a: a)
    }

    /// The same picture on a bigger, transparent canvas (`margin` pixels on every side).
    public func padded(by margin: Int) -> PixelImage {
        guard margin > 0, !isEmpty else { return self }
        var result = PixelImage(width: width + 2 * margin, height: height + 2 * margin,
                                originX: originX - margin, originY: originY - margin)
        for y in 0..<height {
            let from = offset(0, y)
            let to = result.offset(margin, y + margin)
            for i in 0..<(width * 4) {
                result.pixels[to + i] = pixels[from + i]
            }
        }
        return result
    }

    /// Smooth sample at a position. Pixel (i, j) covers the square from (i, j) to (i + 1, j + 1), so its
    /// centre is at (i + 0.5, j + 0.5). Positions outside the picture repeat the nearest edge pixel,
    /// which avoids transparent borders.
    public func sample(x: Double, y: Double) -> (r: Float, g: Float, b: Float, a: Float) {
        guard width > 0, height > 0 else { return (0, 0, 0, 0) }
        let fx = min(max(x - 0.5, -1e9), 1e9)
        let fy = min(max(y - 0.5, -1e9), 1e9)
        let x0f = fx.rounded(.down)
        let y0f = fy.rounded(.down)
        let tx = Float(fx - x0f)
        let ty = Float(fy - y0f)
        let x0 = min(max(Int(x0f), 0), width - 1)
        let x1 = min(max(Int(x0f) + 1, 0), width - 1)
        let y0 = min(max(Int(y0f), 0), height - 1)
        let y1 = min(max(Int(y0f) + 1, 0), height - 1)
        let a = pixel(x0, y0), b = pixel(x1, y0), c = pixel(x0, y1), d = pixel(x1, y1)
        func mix(_ p: Float, _ q: Float, _ r: Float, _ s: Float) -> Float {
            let top = p + (q - p) * tx
            let bottom = r + (s - r) * tx
            return top + (bottom - top) * ty
        }
        return (mix(a.r, b.r, c.r, d.r), mix(a.g, b.g, c.g, d.g), mix(a.b, b.b, c.b, d.b), mix(a.a, b.a, c.a, d.a))
    }

    /// Applies a colour change to the normal (not premultiplied) colours and keeps alpha as it was.
    func mapColors(_ change: (Float, Float, Float) -> (Float, Float, Float)) -> PixelImage {
        var result = self
        for i in 0..<(width * height) {
            let o = i * 4
            let a = pixels[o + 3]
            if a <= 0 { continue }
            let inverse = 1 / a
            let changed = change(pixels[o] * inverse, pixels[o + 1] * inverse, pixels[o + 2] * inverse)
            result.pixels[o] = min(max(changed.0, 0), 1) * a
            result.pixels[o + 1] = min(max(changed.1, 0), 1) * a
            result.pixels[o + 2] = min(max(changed.2, 0), 1) * a
        }
        return result
    }
}
