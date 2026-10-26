import CoreGraphics
import Foundation
import MotionCore

/// Converts between Apple's CGImage and MotionCore's PixelImage (the picture type the effects work on).
enum PixelBridge {
    static let colorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    /// A picture with premultiplied alpha, 8 bits per channel, as numbers from 0 to 1.
    static func makePixelImage(from image: CGImage) -> PixelImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0, width * height <= 16_000_000 else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var pixels = [Float](repeating: 0, count: bytes.count)
        for index in 0..<bytes.count {
            pixels[index] = Float(bytes[index]) / 255
        }
        return PixelImage(width: width, height: height, pixels: pixels)
    }

    static func makeCGImage(from image: PixelImage) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for index in 0..<(width * height) {
            let o = index * 4
            let alpha = min(max(image.pixels[o + 3], 0), 1)
            for channel in 0..<3 {
                // Premultiplied colour can never be brighter than alpha.
                let value = min(max(image.pixels[o + channel], 0), alpha)
                bytes[o + channel] = UInt8((value * 255).rounded())
            }
            bytes[o + 3] = UInt8((alpha * 255).rounded())
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: colorSpace,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
