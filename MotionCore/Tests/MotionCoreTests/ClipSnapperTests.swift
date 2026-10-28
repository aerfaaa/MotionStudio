import XCTest
@testable import MotionCore

final class ClipSnapperTests: XCTestCase {
    func testClipEndSnapsToAnotherClipStart() {
        let otherID = UUID()
        let other = ClipInterval(id: otherID, inPoint: Time(seconds: 4), outPoint: Time(seconds: 7))
        let result = ClipSnapper.snapStart(
            proposedStart: Time(seconds: 1.02),
            clipDuration: Time(seconds: 3),
            compositionDuration: Time(seconds: 10),
            frameRate: .fps30,
            otherClips: [other],
            pointsPerSecond: 100,
            thresholdPoints: 10
        )
        XCTAssertEqual(result.start, .init(seconds: 1))
        XCTAssertEqual(result.snapKey, "end-\(otherID.uuidString)-start")
    }

    func testClipStartSnapsToAnotherClipEnd() {
        let otherID = UUID()
        let other = ClipInterval(id: otherID, inPoint: Time(seconds: 1), outPoint: Time(seconds: 4))
        let result = ClipSnapper.snapStart(
            proposedStart: Time(seconds: 4.04),
            clipDuration: Time(seconds: 2),
            compositionDuration: Time(seconds: 10),
            frameRate: .fps30,
            otherClips: [other],
            pointsPerSecond: 100,
            thresholdPoints: 10
        )
        XCTAssertEqual(result.start, .init(seconds: 4))
        XCTAssertEqual(result.snapKey, "start-\(otherID.uuidString)-end")
    }

    func testSnappingCanBeDisabledButClipStillStaysFrameAligned() {
        let result = ClipSnapper.snapStart(
            proposedStart: Time(seconds: 1.047),
            clipDuration: Time(seconds: 2),
            compositionDuration: Time(seconds: 10),
            frameRate: .fps30,
            otherClips: [ClipInterval(id: UUID(), inPoint: Time(seconds: 1), outPoint: Time(seconds: 3))],
            pointsPerSecond: 100,
            enabled: false
        )
        XCTAssertNil(result.snapKey)
        XCTAssertEqual(result.start, .init(seconds: 1 + 1.0 / 30.0))
    }

    func testClipCannotMovePastCompositionEnd() {
        let result = ClipSnapper.snapStart(
            proposedStart: Time(seconds: 9.9),
            clipDuration: Time(seconds: 2),
            compositionDuration: Time(seconds: 10),
            frameRate: .fps30,
            otherClips: [],
            pointsPerSecond: 100
        )
        XCTAssertLessThanOrEqual(result.start.seconds, 8.000001)
    }
}
