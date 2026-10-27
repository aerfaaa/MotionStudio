import XCTest
@testable import MotionCore

final class PlaybackClockTests: XCTestCase {

    func testFramesFollowRealTimeAt29_97() {
        let clock = PlaybackClock(frameRate: .fps29_97, frameCount: 1000, loops: false, startFrame: 0, startWallTime: 0)
        XCTAssertEqual(clock.frame(atWallTime: 0), 0)
        XCTAssertEqual(clock.frame(atWallTime: 0.033), 0)   // one frame lasts 0.03337 s
        XCTAssertEqual(clock.frame(atWallTime: 0.034), 1)
        XCTAssertEqual(clock.frame(atWallTime: 1.001), 30)  // exactly 30 frames in 1.001 s
        XCTAssertEqual(clock.frame(atWallTime: 10.01), 300)
    }

    func testPlaybackSpeedDoesNotDependOnDisplayRefreshRate() {
        // Pretend the screen refreshes 120 times a second while a 24 fps composition plays.
        let clock = PlaybackClock(frameRate: .fps24, frameCount: 1000, loops: false, startFrame: 0, startWallTime: 0)
        var shown = Set<Int64>()
        var previous: Int64 = -1
        for tick in 0..<120 {
            let frame = clock.frame(atWallTime: Double(tick) / 120.0)
            XCTAssertGreaterThanOrEqual(frame, previous, "frames never go backwards")
            previous = frame
            shown.insert(frame)
        }
        XCTAssertEqual(shown.count, 24, "exactly 24 different frames in one second")
        XCTAssertEqual(clock.frame(atWallTime: 1.0), 24)
    }

    func testHighFrameRatesAreNotCapped() {
        let clock = PlaybackClock(frameRate: .fps120, frameCount: 10_000, loops: false, startFrame: 0, startWallTime: 0)
        XCTAssertEqual(clock.frame(atWallTime: 1.0), 120)
        let sixty = PlaybackClock(frameRate: .fps59_94, frameCount: 10_000, loops: false, startFrame: 0, startWallTime: 0)
        XCTAssertEqual(sixty.frame(atWallTime: 1.001), 60)
    }

    func testPlaybackStartsFromTheStartFrame() {
        let clock = PlaybackClock(frameRate: .fps30, frameCount: 1000, loops: false, startFrame: 5, startWallTime: 100)
        XCTAssertEqual(clock.frame(atWallTime: 100), 5)
        XCTAssertEqual(clock.frame(atWallTime: 100.1), 8)
        XCTAssertEqual(clock.frame(atWallTime: 90), 5, "a clock that reads earlier than the start stays at the start")
    }

    func testLooping() {
        let clock = PlaybackClock(frameRate: .fps30, frameCount: 10, loops: true, startFrame: 0, startWallTime: 0)
        XCTAssertEqual(clock.frame(atWallTime: 0.5), 5)    // frame 15 wraps to 5
        XCTAssertFalse(clock.hasFinished(atWallTime: 100))
    }

    func testStoppingAtTheLastFrame() {
        let clock = PlaybackClock(frameRate: .fps30, frameCount: 10, loops: false, startFrame: 0, startWallTime: 0)
        XCTAssertEqual(clock.frame(atWallTime: 0.5), 9)
        XCTAssertTrue(clock.hasFinished(atWallTime: 0.5))
        XCTAssertFalse(clock.hasFinished(atWallTime: 0.1))
    }

    func testEmptyCompositionDoesNotCrash() {
        let clock = PlaybackClock(frameRate: .fps30, frameCount: 0, loops: true, startFrame: 0, startWallTime: 0)
        XCTAssertEqual(clock.frame(atWallTime: 5), 0)
    }
}
