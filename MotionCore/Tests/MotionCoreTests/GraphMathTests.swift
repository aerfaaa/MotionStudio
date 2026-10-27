import XCTest
@testable import MotionCore

/// Checks the maths behind the Value Graph and Speed Graph.
/// Expected numbers were worked out separately (with a script), not by this code.
final class GraphMathTests: XCTestCase {

    private func t(_ seconds: Double) -> Time { Time(seconds: seconds) }

    func testDerivativeOfALinearCurveIsOne() {
        XCTAssertEqual(BezierEase(0, 0, 1, 1).derivative(at: 0.3), 1.0, accuracy: 1e-9)
    }

    func testDerivativeKnownValues() {
        XCTAssertEqual(BezierEase.easeInOut.derivative(at: 0.5), 1.7241379310, accuracy: 1e-6)
        XCTAssertEqual(BezierEase.easeInOut.derivative(at: 0.25), 1.0592618412, accuracy: 1e-6)
        XCTAssertEqual(BezierEase.easeIn.derivative(at: 0.5), 1.0739787798, accuracy: 1e-6)
        XCTAssertEqual(BezierEase.easeIn.derivative(at: 0.3), 0.7683893179, accuracy: 1e-6)
    }

    func testDerivativeMatchesASlopeMeasuredFromTheCurve() {
        let curves = [BezierEase.easeInOut, .easeIn, .easeOut, BezierEase(0.34, 1.56, 0.64, 1)]
        for curve in curves {
            for x in [0.1, 0.3, 0.5, 0.7, 0.9] {
                let h = 1e-5
                let measured = (curve.solve(x + h) - curve.solve(x - h)) / (2 * h)
                XCTAssertEqual(curve.derivative(at: x), measured, accuracy: 1e-3, "\(curve) at \(x)")
            }
        }
    }

    func testOvershootCurveGoesPastTheEndThenSettles() {
        let curve = BezierEase(0.34, 1.56, 0.64, 1)
        XCTAssertEqual(curve.solve(0.8), 1.0424743803, accuracy: 1e-6)
        XCTAssertEqual(curve.solve(1), 1)
        XCTAssertLessThan(curve.derivative(at: 0.7), 0, "moving backwards while settling")
    }

    func testSoftLandingStartsFastAndEndsGently() {
        let curve = EasingPreset.softLanding.interpolation
        guard case .bezier(let ease) = curve else { return XCTFail("expected a Bezier curve") }
        XCTAssertEqual(ease.solve(0.1), 0.4943906171, accuracy: 1e-6)
        XCTAssertEqual(ease.solve(0.5), 0.9717791053, accuracy: 1e-6)
        XCTAssertGreaterThan(ease.derivative(at: 0.1), ease.derivative(at: 0.9))
    }

    func testSpeedOfLinearAndHoldAndOutsideTheKeyframes() {
        let linear = AnimatedProperty(0.0, keyframes: [
            Keyframe(time: t(0), value: 0.0), Keyframe(time: t(2), value: 100.0),
        ])
        XCTAssertEqual(linear.speed(at: t(1)), 50, accuracy: 1e-9)
        XCTAssertEqual(linear.speed(at: t(0)), 50, accuracy: 1e-9)
        XCTAssertEqual(linear.speed(at: t(2)), 0, "after the last keyframe nothing moves")
        XCTAssertEqual(linear.speed(at: t(-1)), 0, "before the first keyframe nothing moves")

        let held = AnimatedProperty(0.0, keyframes: [
            Keyframe(time: t(0), value: 0.0, outgoing: .hold), Keyframe(time: t(2), value: 100.0),
        ])
        XCTAssertEqual(held.speed(at: t(1)), 0)

        XCTAssertEqual(AnimatedProperty(5.0).speed(at: t(1)), 0)
    }

    func testSpeedOfAnEasedSegment() {
        let eased = AnimatedProperty(0.0, keyframes: [
            Keyframe(time: t(0), value: 0.0, outgoing: .bezier(.easeInOut)), Keyframe(time: t(2), value: 100.0),
        ])
        XCTAssertEqual(eased.speed(at: t(1)), 86.2068965517, accuracy: 1e-5)
        XCTAssertEqual(eased.speed(at: t(0.5)), 52.9630920587, accuracy: 1e-5)
    }

    func testSpeedOfAVectorProperty() {
        let move = AnimatedProperty(Vec2.zero, keyframes: [
            Keyframe(time: t(0), value: Vec2(x: 0, y: 0)), Keyframe(time: t(5), value: Vec2(x: 300, y: 400)),
        ])
        XCTAssertEqual(move.speed(at: t(2)), 100, accuracy: 1e-9)
    }

    func testTheAreaUnderTheSpeedCurveIsTheTotalChange() {
        // Adding up speed x time over a segment must give back the value change. This ties the
        // Speed Graph and the Value Graph together.
        let eased = AnimatedProperty(0.0, keyframes: [
            Keyframe(time: t(0), value: 10.0, outgoing: .bezier(.easeInOut)), Keyframe(time: t(4), value: 90.0),
        ])
        let steps = 4000
        var total = 0.0
        for i in 0..<steps {
            let midpoint = (Double(i) + 0.5) / Double(steps) * 4
            total += eased.speed(at: t(midpoint)) * (4.0 / Double(steps))
        }
        XCTAssertEqual(total, 80, accuracy: 0.05)
    }

    func testSegmentLookup() {
        let property = AnimatedProperty(0.0, keyframes: [
            Keyframe(time: t(0), value: 0.0), Keyframe(time: t(1), value: 1.0), Keyframe(time: t(3), value: 2.0),
        ])
        let middle = property.segment(at: t(2))
        XCTAssertEqual(middle?.from.time, t(1))
        XCTAssertEqual(middle?.to.time, t(3))
        XCTAssertEqual(middle?.progress ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertNil(property.segment(at: t(3)))
        XCTAssertNil(property.segment(at: t(-0.5)))
        XCTAssertNil(AnimatedProperty(0.0).segment(at: t(1)))
    }

    func testSampledValuesForTheValueGraph() {
        let property = AnimatedProperty(0.0, keyframes: [
            Keyframe(time: t(0), value: 0.0), Keyframe(time: t(4), value: 40.0),
        ])
        let samples = property.sampledValues(from: t(0), to: t(4), count: 5)
        XCTAssertEqual(samples.map { $0.value }, [0, 10, 20, 30, 40])
        XCTAssertEqual(samples.first?.time, t(0))
        XCTAssertEqual(samples.last?.time, t(4))
        XCTAssertTrue(property.sampledValues(from: t(4), to: t(0), count: 5).isEmpty)
    }

    func testFrameAccurateEvaluationAtFractionalFrameRates() {
        let rate = FrameRate.fps29_97
        let property = AnimatedProperty(0.0, keyframes: [
            Keyframe(time: rate.time(ofFrame: 0), value: 0.0), Keyframe(time: rate.time(ofFrame: 150), value: 150.0),
        ])
        for frame in [0, 1, 37, 99, 149] as [Int64] {
            XCTAssertEqual(property.value(at: rate.time(ofFrame: frame)), Double(frame), accuracy: 1e-9)
        }
    }
}
