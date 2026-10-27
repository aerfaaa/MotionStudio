import XCTest
@testable import MotionCore

final class AnimationTests: XCTestCase {

    private func t(_ seconds: Double) -> Time { Time(seconds: seconds) }

    func testNoKeyframesReturnsStaticValue() {
        let property = AnimatedProperty(7.0)
        XCTAssertEqual(property.value(at: t(3)), 7.0)
        XCTAssertFalse(property.isAnimated)
    }

    func testLinearMidpoint() {
        let property = AnimatedProperty(0.0, keyframes: [
            Keyframe(time: t(0), value: 0.0),
            Keyframe(time: t(2), value: 100.0),
        ])
        XCTAssertEqual(property.value(at: t(1)), 50.0, accuracy: 1e-9)
        XCTAssertEqual(property.value(at: t(0.5)), 25.0, accuracy: 1e-9)
    }

    func testHoldKeepsValueUntilNextKeyframe() {
        let property = AnimatedProperty(0.0, keyframes: [
            Keyframe(time: t(0), value: 10.0, outgoing: .hold),
            Keyframe(time: t(2), value: 20.0),
        ])
        XCTAssertEqual(property.value(at: t(1.999)), 10.0)
        XCTAssertEqual(property.value(at: t(2)), 20.0)
    }

    func testValuesAreClampedBeforeFirstAndAfterLastKeyframe() {
        let property = AnimatedProperty(0.0, keyframes: [
            Keyframe(time: t(1), value: 5.0),
            Keyframe(time: t(2), value: 9.0),
        ])
        XCTAssertEqual(property.value(at: t(0)), 5.0)
        XCTAssertEqual(property.value(at: t(10)), 9.0)
    }

    func testSingleKeyframeActsAsConstant() {
        let property = AnimatedProperty(0.0, keyframes: [Keyframe(time: t(1), value: 4.0)])
        XCTAssertEqual(property.value(at: t(0)), 4.0)
        XCTAssertEqual(property.value(at: t(1)), 4.0)
        XCTAssertEqual(property.value(at: t(9)), 4.0)
    }

    func testVectorInterpolation() {
        let property = AnimatedProperty(Vec2.zero, keyframes: [
            Keyframe(time: t(0), value: Vec2(x: 0, y: 0)),
            Keyframe(time: t(4), value: Vec2(x: 100, y: 200)),
        ])
        assertEqual(property.value(at: t(1)), Vec2(x: 25, y: 50))
    }

    func testCorrectSegmentIsUsedWithManyKeyframes() {
        let property = AnimatedProperty(0.0, keyframes: [
            Keyframe(time: t(0), value: 0.0),
            Keyframe(time: t(1), value: 10.0),
            Keyframe(time: t(3), value: 30.0),
            Keyframe(time: t(4), value: 0.0),
        ])
        XCTAssertEqual(property.value(at: t(0.5)), 5.0, accuracy: 1e-9)
        XCTAssertEqual(property.value(at: t(2)), 20.0, accuracy: 1e-9)
        XCTAssertEqual(property.value(at: t(3.5)), 15.0, accuracy: 1e-9)
    }

    func testBezierEaseKnownValues() {
        let ease = BezierEase.easeInOut
        XCTAssertEqual(ease.solve(0), 0)
        XCTAssertEqual(ease.solve(1), 1)
        XCTAssertEqual(ease.solve(0.5), 0.5, accuracy: 1e-9)
        XCTAssertEqual(ease.solve(0.25), 0.1291619310, accuracy: 1e-6)
        XCTAssertEqual(ease.solve(0.75), 0.8708380690, accuracy: 1e-6)
        XCTAssertEqual(BezierEase.easeIn.solve(0.5), 0.3153568126, accuracy: 1e-6)
        XCTAssertEqual(BezierEase(0, 0, 1, 1).solve(0.3), 0.3, accuracy: 1e-9)
    }

    func testBezierEaseNeverGoesBackwards() {
        let ease = BezierEase.easeInOut
        var previous = -1.0
        for i in 0...1000 {
            let value = ease.solve(Double(i) / 1000)
            XCTAssertGreaterThanOrEqual(value, previous - 1e-12)
            previous = value
        }
    }

    func testBezierKeyframeSegmentUsesTheCurve() {
        let property = AnimatedProperty(0.0, keyframes: [
            Keyframe(time: t(0), value: 0.0, outgoing: .bezier(.easeInOut)),
            Keyframe(time: t(4), value: 100.0),
        ])
        XCTAssertEqual(property.value(at: t(1)), 12.91619310, accuracy: 1e-4)
        XCTAssertEqual(property.value(at: t(2)), 50.0, accuracy: 1e-6)
    }

    func testSetKeyframeKeepsOrderAndReplacesSameTime() {
        var property = AnimatedProperty(0.0)
        property.setKeyframe(at: t(2), value: 20)
        property.setKeyframe(at: t(0), value: 0)
        property.setKeyframe(at: t(1), value: 10)
        XCTAssertEqual(property.keyframes.map { $0.time }, [t(0), t(1), t(2)])
        property.setKeyframe(at: t(1), value: 99, interpolation: .hold)
        XCTAssertEqual(property.keyframes.count, 3)
        XCTAssertEqual(property.keyframe(at: t(1))?.value, 99)
        XCTAssertEqual(property.keyframe(at: t(1))?.outgoing, .hold)
    }

    func testRemovingLastKeyframeFreezesTheValue() {
        var property = AnimatedProperty(0.0)
        property.setKeyframe(at: t(1), value: 42)
        XCTAssertTrue(property.removeKeyframe(at: t(1)))
        XCTAssertFalse(property.isAnimated)
        XCTAssertEqual(property.staticValue, 42)
        XCTAssertFalse(property.removeKeyframe(at: t(1)))
    }

    func testInitRepairsUnsortedAndDuplicateKeyframes() {
        let property = AnimatedProperty(0.0, keyframes: [
            Keyframe(time: t(2), value: 20.0),
            Keyframe(time: t(1), value: 10.0),
            Keyframe(time: t(1), value: 11.0),
        ])
        XCTAssertEqual(property.keyframes.count, 2)
        XCTAssertEqual(property.keyframes.map { $0.time }, [t(1), t(2)])
    }

    func testCodableRoundTrip() throws {
        var property = AnimatedProperty(Vec2(x: 1, y: 2))
        property.setKeyframe(at: t(0), value: Vec2(x: 0, y: 0), interpolation: .bezier(.easeOut))
        property.setKeyframe(at: t(1), value: Vec2(x: 5, y: 5), interpolation: .hold)
        let data = try JSONEncoder().encode(property)
        let decoded = try JSONDecoder().decode(AnimatedProperty<Vec2>.self, from: data)
        XCTAssertEqual(decoded, property)
    }
}
