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
        // Allow up to 120 Hz so 50, 59.94, 60 and 120 fps compositions can be shown smoothly
        // on screens that support it. (iPhones also need CADisableMinimumFrameDurationOnPhone in Info.plist.)
        newLink.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
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
