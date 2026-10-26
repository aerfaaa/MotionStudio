import Foundation

/// Works out which frame to show during playback.
///
/// The frame is calculated from how much real time has passed since playback started,
/// not by counting screen refreshes. That is why a 24 fps composition plays at the right
/// speed on a 60 Hz or 120 Hz display, and why frame drops never make the video run slow.
public struct PlaybackClock: Equatable {
    public let frameRate: FrameRate
    public let frameCount: Int64
    public let loops: Bool
    public let startFrame: Int64
    /// Wall-clock time (in seconds, from any steady clock) when playback began.
    public let startWallTime: Double

    public init(frameRate: FrameRate, frameCount: Int64, loops: Bool,
                startFrame: Int64, startWallTime: Double) {
        self.frameRate = frameRate
        self.frameCount = frameCount
        self.loops = loops
        self.startFrame = startFrame
        self.startWallTime = startWallTime
    }

    private func rawFrame(atWallTime wallTime: Double) -> Int64 {
        let elapsed = max(0, wallTime - startWallTime)
        return startFrame + frameRate.frameIndex(at: Time(seconds: elapsed))
    }

    /// The frame that should be on screen at this wall-clock time.
    public func frame(atWallTime wallTime: Double) -> Int64 {
        guard frameCount > 0 else { return 0 }
        let raw = rawFrame(atWallTime: wallTime)
        if loops { return raw % frameCount }
        return min(raw, frameCount - 1)
    }

    /// True once a non-looping playback has reached its last frame.
    public func hasFinished(atWallTime wallTime: Double) -> Bool {
        guard !loops, frameCount > 0 else { return false }
        return rawFrame(atWallTime: wallTime) >= frameCount - 1
    }
}
