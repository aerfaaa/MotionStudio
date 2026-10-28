import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import Vision

/// Generates an in-between image by estimating motion in both directions and warping each
/// source toward the requested time. Used for export-time slow-motion frame synthesis.
enum OpticalFlowInterpolator {
    static func interpolate(_ first: CGImage, _ second: CGImage, amount: CGFloat) -> CGImage? {
        let t = min(1, max(0, amount))
        guard first.width == second.width, first.height == second.height else { return nil }
        if t <= 0.001 { return first }
        if t >= 0.999 { return second }
        guard let forward = flow(from: first, to: second),
              let backward = flow(from: second, to: first),
              let a = rgba(first), let b = rgba(second),
              let f = flowValues(forward), let r = flowValues(backward) else {
            return blend(first, second, amount: t)
        }
        let width = first.width, height = first.height
        var output = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                let fx = f[i * 2] * Float(width), fy = f[i * 2 + 1] * Float(height)
                let bx = r[i * 2] * Float(width), by = r[i * 2 + 1] * Float(height)
                let ap = sample(a, width: width, height: height,
                                x: CGFloat(x) - CGFloat(fx) * t,
                                y: CGFloat(y) - CGFloat(fy) * t)
                let bp = sample(b, width: width, height: height,
                                x: CGFloat(x) - CGFloat(bx) * (1 - t),
                                y: CGFloat(y) - CGFloat(by) * (1 - t))
                let base = i * 4
                for c in 0..<4 { output[base + c] = UInt8(min(255, max(0, (Double(ap[c]) * Double(1 - t) + Double(bp[c]) * Double(t)).rounded()))) }
            }
        }
        return makeImage(output, width: width, height: height)
    }

    private static func flow(from image: CGImage, to target: CGImage) -> CVPixelBuffer? {
        let request = VNGenerateOpticalFlowRequest(targetedCGImage: target, options: [:])
        request.computationAccuracy = .high
        request.outputPixelFormat = kCVPixelFormatType_TwoComponent32Float
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            return (request.results?.first as? VNPixelBufferObservation)?.pixelBuffer
        } catch { return nil }
    }

    private static func flowValues(_ buffer: CVPixelBuffer) -> [Float]? {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_TwoComponent32Float else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let stride = CVPixelBufferGetBytesPerRow(buffer) / MemoryLayout<Float>.size
        let values = base.assumingMemoryBound(to: Float.self)
        var result = [Float](repeating: 0, count: width * height * 2)
        for y in 0..<height { for x in 0..<width {
            let src = y * stride + x * 2, dst = (y * width + x) * 2
            result[dst] = values[src]; result[dst + 1] = values[src + 1]
        }}
        return result
    }

    private static func rgba(_ image: CGImage) -> [UInt8]? {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let ok = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return ok ? bytes : nil
    }

    private static func sample(_ pixels: [UInt8], width: Int, height: Int, x: CGFloat, y: CGFloat) -> [UInt8] {
        let px = min(CGFloat(width - 1), max(0, x)), py = min(CGFloat(height - 1), max(0, y))
        let x0 = Int(px), y0 = Int(py), x1 = min(width - 1, x0 + 1), y1 = min(height - 1, y0 + 1)
        let tx = Double(px - CGFloat(x0)), ty = Double(py - CGFloat(y0))
        let i00 = (y0 * width + x0) * 4, i10 = (y0 * width + x1) * 4
        let i01 = (y1 * width + x0) * 4, i11 = (y1 * width + x1) * 4
        return (0..<4).map { c in
            let top = Double(pixels[i00 + c]) * (1 - tx) + Double(pixels[i10 + c]) * tx
            let bottom = Double(pixels[i01 + c]) * (1 - tx) + Double(pixels[i11 + c]) * tx
            return UInt8(min(255, max(0, (top * (1 - ty) + bottom * ty).rounded())))
        }
    }

    private static func makeImage(_ bytes: [UInt8], width: Int, height: Int) -> CGImage? {
        let data = Data(bytes)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true,
                       intent: .defaultIntent)
    }

    private static func blend(_ first: CGImage, _ second: CGImage, amount: CGFloat) -> CGImage? {
        let ciA = CIImage(cgImage: first), ciB = CIImage(cgImage: second)
        guard let filter = CIFilter(name: "CIDissolveTransition") else { return nil }
        filter.setValue(ciA, forKey: kCIInputImageKey)
        filter.setValue(ciB, forKey: kCIInputTargetImageKey)
        filter.setValue(amount, forKey: kCIInputTimeKey)
        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: ciA.extent)
    }
}
