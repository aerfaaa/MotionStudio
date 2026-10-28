import SwiftUI
import AVFAudio

/// Lightweight cached waveform for audio timeline clips. Peak extraction happens off the UI thread;
/// drawing is a single Canvas pass rather than hundreds of SwiftUI subviews.
struct AudioWaveformView: View {
    let url: URL
    let tint: Color
    var barCount: Int = 180

    @State private var peaks: [CGFloat] = []

    var body: some View {
        Canvas { context, size in
            guard !peaks.isEmpty, size.width > 0, size.height > 0 else {
                var placeholder = Path()
                placeholder.move(to: CGPoint(x: 0, y: size.height / 2))
                placeholder.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                context.stroke(placeholder, with: .color(tint.opacity(0.45)), lineWidth: 1)
                return
            }
            let count = min(peaks.count, max(1, Int(size.width / 2.5)))
            let step = CGFloat(count > 0 ? peaks.count : 1) / CGFloat(count)
            let barWidth = max(1, size.width / CGFloat(count) * 0.62)
            for index in 0..<count {
                let peakIndex = min(peaks.count - 1, Int(CGFloat(index) * step))
                let amplitude = max(0.06, min(1, peaks[peakIndex]))
                let height = max(1, amplitude * size.height * 0.88)
                let rect = CGRect(x: CGFloat(index) * size.width / CGFloat(count),
                                  y: (size.height - height) / 2,
                                  width: barWidth, height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2),
                             with: .color(tint.opacity(0.92)))
            }
        }
        .accessibilityLabel("Audio waveform")
        .task(id: url) {
            peaks = []
            let targetCount = max(32, barCount)
            let result = await Task.detached(priority: .utility) {
                Self.extractPeaks(url: url, count: targetCount)
            }.value
            guard !Task.isCancelled else { return }
            peaks = result
        }
    }

    private static func extractPeaks(url: URL, count: Int) -> [CGFloat] {
        guard let file = try? AVAudioFile(forReading: url) else { return [] }
        let totalFrames = Int64(file.length)
        guard totalFrames > 0 else { return [] }
        let bins = max(32, count)
        let framesPerBin = max(Int64(1), (totalFrames + Int64(bins) - 1) / Int64(bins))
        var result = Array(repeating: CGFloat(0), count: bins)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096) else { return [] }
        var absoluteFrame: Int64 = 0
        while absoluteFrame < totalFrames {
            do { try file.read(into: buffer) } catch { break }
            let frameCount = Int(buffer.frameLength)
            if frameCount == 0 { break }
            if let channels = buffer.floatChannelData {
                let channelCount = Int(buffer.format.channelCount)
                for frame in 0..<frameCount {
                    var peak: Float = 0
                    for channel in 0..<channelCount {
                        peak = max(peak, abs(channels[channel][frame]))
                    }
                    let bin = min(bins - 1, Int((absoluteFrame + Int64(frame)) / framesPerBin))
                    result[bin] = max(result[bin], CGFloat(peak))
                }
            } else if let channels = buffer.int16ChannelData {
                let channelCount = Int(buffer.format.channelCount)
                for frame in 0..<frameCount {
                    var peak: Int32 = 0
                    for channel in 0..<channelCount {
                        peak = max(peak, abs(Int32(channels[channel][frame])))
                    }
                    let bin = min(bins - 1, Int((absoluteFrame + Int64(frame)) / framesPerBin))
                    result[bin] = max(result[bin], CGFloat(peak) / CGFloat(Int16.max))
                }
            }
            absoluteFrame += Int64(frameCount)
        }
        let maxPeak = max(result.max() ?? 0, 0.001)
        return result.map { min(1, $0 / maxPeak) }
    }
}
