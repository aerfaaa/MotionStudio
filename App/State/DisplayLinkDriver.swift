import UIKit

/// Calls `onTick` once per screen refresh while playing. It only supplies the clock time;
/// which composition frame to show is decided by `PlaybackClock` from real elapsed time,
/// so the composition frame rate never depends on the screen's refresh rate.
@MainActor
final class DisplayLinkDriver: NSObject {
    var onTick: (@MainActor (Double) -> Void)?
    private var link: CADisplayLink?

    func start() {
        guard link == nil else { return }
        let newLink = CADisplayLink(target: self, selector: #selector(handleTick(_:)))
        // Keep editor playback at a 60 Hz callback ceiling. The composition clock still chooses
        // frames from elapsed time, while older devices avoid needless 120 Hz main-thread callbacks.
        newLink.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        newLink.add(to: .main, forMode: .common)
        link = newLink
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func handleTick(_ sender: CADisplayLink) {
        onTick?(sender.timestamp)
    }
}
