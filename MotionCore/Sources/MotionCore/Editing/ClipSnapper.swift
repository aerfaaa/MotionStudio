import Foundation

/// A clip interval used by timeline snapping. Intervals are composition-relative.
public struct ClipInterval: Equatable, Sendable {
    public let id: UUID
    public let inPoint: Time
    public let outPoint: Time

    public init(id: UUID, inPoint: Time, outPoint: Time) {
        self.id = id
        self.inPoint = inPoint
        self.outPoint = outPoint
    }
}

/// Result of moving a clip. `snapKey` changes when the active edge target changes, allowing the UI
/// to emit one haptic on entry instead of buzzing continuously while the finger stays snapped.
public struct ClipSnapResult: Equatable, Sendable {
    public let start: Time
    public let snapKey: String?

    public init(start: Time, snapKey: String?) {
        self.start = start
        self.snapKey = snapKey
    }
}

/// Frame-aligned clip movement with optional edge snapping. The threshold is measured in screen
/// points so the interaction stays predictable at different timeline zoom levels.
public enum ClipSnapper {
    public static func snapStart(proposedStart: Time,
                                 clipDuration: Time,
                                 compositionDuration: Time,
                                 frameRate: FrameRate,
                                 otherClips: [ClipInterval],
                                 pointsPerSecond: Double,
                                 thresholdPoints: Double = 10,
                                 enabled: Bool = true) -> ClipSnapResult {
        let durationSeconds = max(0, clipDuration.seconds)
        let compositionSeconds = max(0, compositionDuration.seconds)
        let maxStart = max(0, compositionSeconds - durationSeconds)
        let proposed = min(maxStart, max(0, nearestFrame(proposedStart, frameRate: frameRate).seconds))
        guard enabled, pointsPerSecond.isFinite, pointsPerSecond > 0, thresholdPoints >= 0 else {
            return ClipSnapResult(start: nearestFrame(Time(seconds: proposed), frameRate: frameRate), snapKey: nil)
        }

        var anchors: [(time: Double, key: String)] = [
            (0, "composition-start"),
            (compositionSeconds, "composition-end")
        ]
        for clip in otherClips {
            anchors.append((clip.inPoint.seconds, "\(clip.id.uuidString)-start"))
            anchors.append((clip.outPoint.seconds, "\(clip.id.uuidString)-end"))
        }

        var best: (start: Double, key: String, distance: Double)?
        for anchor in anchors {
            let startDistance = abs(proposed - anchor.time) * pointsPerSecond
            if startDistance <= thresholdPoints {
                let candidate = (start: min(maxStart, max(0, anchor.time)), key: "start-\(anchor.key)", distance: startDistance)
                if best == nil || candidate.distance < best!.distance { best = candidate }
            }
            let endAlignedStart = anchor.time - durationSeconds
            let endDistance = abs(proposed - endAlignedStart) * pointsPerSecond
            if endDistance <= thresholdPoints {
                let candidate = (start: min(maxStart, max(0, endAlignedStart)), key: "end-\(anchor.key)", distance: endDistance)
                if best == nil || candidate.distance < best!.distance { best = candidate }
            }
        }
        guard let best else {
            return ClipSnapResult(start: nearestFrame(Time(seconds: proposed), frameRate: frameRate), snapKey: nil)
        }
        return ClipSnapResult(start: nearestFrame(Time(seconds: best.start), frameRate: frameRate), snapKey: best.key)
    }

    private static func nearestFrame(_ time: Time, frameRate: FrameRate) -> Time {
        let lowerIndex = frameRate.frameIndex(at: time)
        let lower = frameRate.time(ofFrame: lowerIndex)
        let upper = frameRate.time(ofFrame: lowerIndex + 1)
        return abs(time.seconds - lower.seconds) <= abs(upper.seconds - time.seconds) ? lower : upper
    }
}
