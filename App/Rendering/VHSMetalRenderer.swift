import CoreGraphics
import Foundation
import Metal
import MotionCore

/// GPU fast path for the VHS effect. The CPU effect remains the fallback if Metal is unavailable.
enum VHSMetalRenderer {
    private struct Uniforms {
        var intensity: Float
        var tracking: Float
        var scanlines: Float
        var chromaLoss: Float
        var noise: Float
        var phase: Float
        var tapeMode: UInt32
        var scale: Float
    }

    private static let device = MTLCreateSystemDefaultDevice()
    private static let pipeline: MTLComputePipelineState? = {
        guard let device,
              let library = device.makeDefaultLibrary(),
              let function = library.makeFunction(name: "vhsKernel") else { return nil }
        return try? device.makeComputePipelineState(function: function)
    }()
    private static let queue = device?.makeCommandQueue()

    static func render(_ image: CGImage, values: EffectValues, scale: Double, phase: Double) -> CGImage? {
        guard let device, let pipeline, let queue,
              image.width > 0, image.height > 0,
              scale.isFinite, scale > 0 else { return nil }

        let width = image.width
        let height = image.height
        let rowBytes = width * 4
        var sourceBytes = [UInt8](repeating: 0, count: rowBytes * height)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue))
        let didDraw = sourceBytes.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let bitmap = CGContext(data: base, width: width, height: height,
                                         bitsPerComponent: 8, bytesPerRow: rowBytes,
                                         space: colorSpace, bitmapInfo: bitmapInfo.rawValue) else { return false }
            bitmap.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard didDraw else { return nil }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
                                                                  width: width, height: height,
                                                                  mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        guard let input = device.makeTexture(descriptor: descriptor),
              let output = device.makeTexture(descriptor: descriptor) else { return nil }
        sourceBytes.withUnsafeBytes { raw in
            if let base = raw.baseAddress {
                input.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                              withBytes: base, bytesPerRow: rowBytes)
            }
        }

        let uniforms = Uniforms(
            intensity: Float(values.scalar("intensity")),
            tracking: Float(values.scalar("tracking") * scale),
            scanlines: Float(values.scalar("scanlines")),
            chromaLoss: Float(values.scalar("chromaLoss")),
            noise: Float(values.scalar("noise")),
            phase: Float(phase),
            tapeMode: UInt32(min(max(values.choice("tapeMode"), 0), 2)),
            scale: Float(scale)
        )
        guard let command = queue.makeCommandBuffer(),
              let encoder = command.makeComputeCommandEncoder() else { return nil }
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(input, index: 0)
        encoder.setTexture(output, index: 1)
        var mutableUniforms = uniforms
        encoder.setBytes(&mutableUniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        let threadWidth = max(1, min(pipeline.threadExecutionWidth, width))
        let threadHeight = max(1, min(pipeline.maxTotalThreadsPerThreadgroup / threadWidth, height))
        encoder.dispatchThreads(MTLSize(width: width, height: height, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: threadWidth, height: threadHeight, depth: 1))
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed else { return nil }

        var outputBytes = [UInt8](repeating: 0, count: rowBytes * height)
        outputBytes.withUnsafeMutableBytes { raw in
            if let base = raw.baseAddress {
                output.getBytes(base, bytesPerRow: rowBytes,
                                from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
            }
        }
        let data = Data(outputBytes) as CFData
        guard let provider = CGDataProvider(data: data),
              let result = CGImage(width: width, height: height,
                                   bitsPerComponent: 8, bitsPerPixel: 32,
                                   bytesPerRow: rowBytes, space: colorSpace,
                                   bitmapInfo: bitmapInfo, provider: provider,
                                   decode: nil, shouldInterpolate: true,
                                   intent: .defaultIntent) else { return nil }
        return result
    }
}
