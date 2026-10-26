import XCTest
@testable import MotionCore

final class TimeTests: XCTestCase {

    private let requiredRates: [(name: String, numerator: Int64, denominator: Int64)] = [
        ("24", 24, 1), ("25", 25, 1), ("30", 30, 1), ("50", 50, 1), ("60", 60, 1),
        ("24000/1001", 24000, 1001), ("30000/1001", 30000, 1001), ("60000/1001", 60000, 1001),
        ("48", 48, 1), ("72", 72, 1), ("90", 90, 1), ("100", 100, 1),
        ("120", 120, 1), ("144", 144, 1), ("240", 240, 1), ("120000/1001", 120000, 1001),
    ]

    func testTicksPerSecondValue() {
        XCTAssertEqual(Time.ticksPerSecond, 141_120_000)
    }

    func testEveryRequiredFrameRateIsExactInTicks() {
        for entry in requiredRates {
            let rate = FrameRate(numerator: entry.numerator, denominator: entry.denominator)!
            XCTAssertTrue(rate.hasExactTickFrames, "\(entry.name) must be exact")
            // frames x ticksPerFrame must equal exactly one denominator-worth of seconds.
            let ticksPerFrame = Time.ticksPerSecond * entry.denominator / entry.numerator
            XCTAssertEqual(ticksPerFrame * entry.numerator, Time.ticksPerSecond * entry.denominator, entry.name)
            XCTAssertEqual(rate.time(ofFrame: 1).ticks, ticksPerFrame, entry.name)
        }
    }

    func testEveryAudioSampleRateIsExactInTicks() {
        let sampleRates: [Int64] = [8000, 11025, 16000, 22050, 32000, 44100, 48000, 88200, 96000, 176400, 192000]
        for sampleRate in sampleRates {
            XCTAssertNotNil(Time.ticksPerAudioSample(sampleRate: sampleRate), "\(sampleRate) Hz")
        }
        XCTAssertEqual(Time.ticksPerAudioSample(sampleRate: 44100), 3200)
        XCTAssertEqual(Time.ticksPerAudioSample(sampleRate: 48000), 2940)
        XCTAssertNil(Time.ticksPerAudioSample(sampleRate: 11), "11 Hz does not divide evenly")
        XCTAssertNil(Time.ticksPerAudioSample(sampleRate: 0))
    }

    func testKnownFrameTimes() {
        XCTAssertEqual(FrameRate.fps29_97.time(ofFrame: 30).ticks, 141_261_120)
        XCTAssertEqual(FrameRate.fps24.time(ofFrame: 24), Time(ticks: Time.ticksPerSecond))
        XCTAssertEqual(FrameRate.fps59_94.time(ofFrame: 1).ticks, 2_354_352)
        XCTAssertEqual(FrameRate.fps30.time(ofFrame: 0), .zero)
    }

    func testNoDriftOver24HoursForFractionalRates() {
        let rates: [FrameRate] = [.fps23_976, .fps29_97, .fps59_94]
        for rate in rates {
            let ticksPerFrame = Time.ticksPerSecond * rate.denominator / rate.numerator
            let lastFrame = Int64(24 * 3600) * rate.numerator / rate.denominator
            for frame in stride(from: Int64(0), through: lastFrame, by: 997) {
                XCTAssertEqual(rate.time(ofFrame: frame).ticks, frame * ticksPerFrame)
            }
            XCTAssertEqual(rate.time(ofFrame: lastFrame).ticks, lastFrame * ticksPerFrame)
        }
        // The very last frame of 24 hours at 29.97 fps, worked out independently.
        XCTAssertEqual(FrameRate.fps29_97.time(ofFrame: 2_589_410).ticks, 12_192_765_224_640)
    }

    func testNonExactRateIsRoundedOncePerFrameAndNeverDrifts() {
        // 100000/7 fps is 9878.4 ticks per frame: not a whole number.
        let rate = FrameRate(numerator: 100_000, denominator: 7)!
        XCTAssertFalse(rate.hasExactTickFrames)
        for frame in stride(from: Int64(0), to: 2_000_000, by: 997) {
            let ticks = rate.time(ofFrame: frame).ticks
            // Error in ticks is |ticks - exact|. Multiply by the numerator to stay in whole numbers:
            // it must be at most half a tick, so at most 50,000 here.
            let scaledError = abs(ticks * 100_000 - frame * Time.ticksPerSecond * 7)
            XCTAssertLessThanOrEqual(scaledError, 50_000)
        }
    }

    func testFrameIndexIsTheExactInverseOfTimeOfFrame() {
        let rates: [FrameRate] = [.fps24, .fps29_97, .fps59_94, .fps60, FrameRate(numerator: 100_000, denominator: 7)!]
        for rate in rates {
            for frame in stride(from: Int64(0), to: 500_000, by: 1009) {
                let start = rate.time(ofFrame: frame)
                XCTAssertEqual(rate.frameIndex(at: start), frame)
                XCTAssertEqual(rate.frameIndex(at: start + Time(ticks: 1)), frame)
                if frame > 0 {
                    XCTAssertEqual(rate.frameIndex(at: start - Time(ticks: 1)), frame - 1)
                }
            }
        }
    }

    func testFrameIndexForNegativeTimes() {
        XCTAssertEqual(FrameRate.fps30.frameIndex(at: Time(ticks: -1)), -1)
        XCTAssertEqual(FrameRate.fps30.frameIndex(at: Time(ticks: -4_704_000)), -1)
        XCTAssertEqual(FrameRate.fps30.frameIndex(at: Time(ticks: -4_704_001)), -2)
        XCTAssertEqual(FrameRate.fps30.time(ofFrame: -2).ticks, -9_408_000)
    }

    func testSnappedMovesToFrameStart() {
        let rate = FrameRate.fps24
        let justAfterFrame3 = rate.time(ofFrame: 3) + Time(ticks: 1000)
        XCTAssertEqual(rate.snapped(justAfterFrame3), rate.time(ofFrame: 3))
    }

    func testFrameCountForDurations() {
        XCTAssertEqual(FrameRate.fps24.frameCount(for: Time(seconds: 5)), 120)
        XCTAssertEqual(FrameRate.fps30.frameCount(for: Time(seconds: 5)), 150)
        XCTAssertEqual(FrameRate.fps60.frameCount(for: Time(seconds: 1)), 60)
        XCTAssertEqual(FrameRate.fps59_94.frameCount(for: Time(seconds: 1)), 60)
        // 5.000 s at 29.97 fps: frame 149 starts before the end, so there are 150 frames.
        XCTAssertEqual(FrameRate.fps29_97.frameCount(for: Time(seconds: 5)), 150)
        XCTAssertEqual(FrameRate.fps30.frameCount(for: .zero), 0)
    }

    func testFrameRateIsReducedAndValidated() {
        let reduced = FrameRate(numerator: 50, denominator: 2)!
        XCTAssertEqual(reduced.numerator, 25)
        XCTAssertEqual(reduced.denominator, 1)
        XCTAssertEqual(FrameRate(numerator: 30000, denominator: 1001)!.denominator, 1001)
        XCTAssertNil(FrameRate(numerator: 0, denominator: 1))
        XCTAssertNil(FrameRate(numerator: 24, denominator: 0))
        XCTAssertNil(FrameRate(numerator: -24, denominator: 1))
    }

    func testFrameRateDisplayNames() {
        XCTAssertEqual(FrameRate.fps24.displayName, "24 fps")
        XCTAssertEqual(FrameRate.fps23_976.displayName, "23.976 fps")
        XCTAssertEqual(FrameRate.fps29_97.displayName, "29.97 fps")
        XCTAssertEqual(FrameRate.fps59_94.displayName, "59.94 fps")
    }

    func testFrameRateCodableRoundTripAndRejectsInvalid() throws {
        let data = try JSONEncoder().encode(FrameRate.fps29_97)
        XCTAssertEqual(try JSONDecoder().decode(FrameRate.self, from: data), .fps29_97)

        let bad = Data(#"{"numerator":30,"denominator":0}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(FrameRate.self, from: bad))
    }

    func testTimeIsSavedAsAPlainNumber() throws {
        let data = try JSONEncoder().encode([Time(ticks: 42)])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "[42]")
        XCTAssertEqual(try JSONDecoder().decode([Time].self, from: data), [Time(ticks: 42)])
    }

    func testMaximumDurationIs24Hours() {
        XCTAssertEqual(Time.maximumDuration.seconds, 86_400, accuracy: 0.0001)
    }
}
