import XCTest
@testable import MotionCore

final class EvaluatorTests: XCTestCase {

    private func composition(_ layers: [Layer], rate: FrameRate = .fps30) -> Composition {
        var comp = makeProject(frameRate: rate).rootComposition
        comp.layers = layers
        return comp
    }

    func testPositionKeyframesAreResolvedPerFrame() {
        let rate = FrameRate.fps30
        let duration = makeProject().rootComposition.duration
        var layer = makeRect(duration: duration, position: Vec2(x: 0, y: 100))
        layer.position.setKeyframe(at: rate.time(ofFrame: 0), value: Vec2(x: 0, y: 100))
        layer.position.setKeyframe(at: rate.time(ofFrame: 30), value: Vec2(x: 300, y: 100))
        let comp = composition([layer])

        let frame = Evaluator.resolve(comp, frame: 15)
        XCTAssertEqual(frame.layers.count, 1)
        // The anchor point (the layer's centre) must land on the animated position.
        let anchorInComp = frame.layers[0].transform.applying(to: Vec2(x: 100, y: 50))
        assertEqual(anchorInComp, Vec2(x: 150, y: 100))
    }

    func testTransformCornersMatchReferenceValues() {
        // 200 x 100 layer, anchor at its centre, placed at (960, 540), scaled 2 x 1, rotated 90 degrees.
        // Expected corners worked out independently with a separate script.
        let duration = makeProject().rootComposition.duration
        let layer = Layer(name: "T", kind: .solid, size: Vec2(x: 200, y: 100), fill: .white,
                          inPoint: .zero, outPoint: duration, position: Vec2(x: 960, y: 540),
                          scale: Vec2(x: 2, y: 1), rotation: 90)
        let frame = Evaluator.resolve(composition([layer]), frame: 0)
        let m = frame.layers[0].transform
        assertEqual(m.applying(to: Vec2(x: 0, y: 0)), Vec2(x: 1010, y: 340))
        assertEqual(m.applying(to: Vec2(x: 200, y: 0)), Vec2(x: 1010, y: 740))
        assertEqual(m.applying(to: Vec2(x: 200, y: 100)), Vec2(x: 910, y: 740))
        assertEqual(m.applying(to: Vec2(x: 0, y: 100)), Vec2(x: 910, y: 340))
        assertEqual(m.applying(to: Vec2(x: 100, y: 50)), Vec2(x: 960, y: 540))
    }

    func testInversionUndoesTheTransform() {
        let duration = makeProject().rootComposition.duration
        let layer = Layer(name: "T", kind: .solid, size: Vec2(x: 200, y: 100), fill: .white,
                          inPoint: .zero, outPoint: duration, position: Vec2(x: 300, y: 400),
                          scale: Vec2(x: 1.5, y: 0.5), rotation: 33)
        let m = Evaluator.localTransform(of: layer, at: .zero)
        let inverse = m.inverted()!
        assertEqual(inverse.applying(to: m.applying(to: Vec2(x: 12, y: 34))), Vec2(x: 12, y: 34))
        XCTAssertNil(Affine2.scale(0, 1).inverted())
    }

    func testInAndOutPointsDecideVisibility() {
        let rate = FrameRate.fps30
        let duration = makeProject().rootComposition.duration
        var layer = makeRect(duration: duration)
        layer.inPoint = rate.time(ofFrame: 10)
        layer.outPoint = rate.time(ofFrame: 20)
        let comp = composition([layer])
        XCTAssertEqual(Evaluator.resolve(comp, frame: 9).layers.count, 0)
        XCTAssertEqual(Evaluator.resolve(comp, frame: 10).layers.count, 1)
        XCTAssertEqual(Evaluator.resolve(comp, frame: 19).layers.count, 1)
        XCTAssertEqual(Evaluator.resolve(comp, frame: 20).layers.count, 0)
    }

    func testHiddenAndNullLayersAreNotDrawn() {
        let duration = makeProject().rootComposition.duration
        var hidden = makeRect(name: "Hidden", duration: duration)
        hidden.isVisible = false
        let null = Layer(name: "Null", kind: .null, size: Vec2(x: 10, y: 10), fill: .white,
                         inPoint: .zero, outPoint: duration, position: .zero)
        let shown = makeRect(name: "Shown", duration: duration)
        let frame = Evaluator.resolve(composition([hidden, null, shown]), frame: 0)
        XCTAssertEqual(frame.layers.map { $0.id }, [shown.id])
    }

    func testDrawOrderIsBottomFirst() {
        let duration = makeProject().rootComposition.duration
        let top = makeRect(name: "Top", duration: duration)
        let bottom = makeRect(name: "Bottom", duration: duration)
        // Index 0 is the top layer of the stack.
        let frame = Evaluator.resolve(composition([top, bottom]), frame: 0)
        XCTAssertEqual(frame.layers.map { $0.id }, [bottom.id, top.id])
    }

    func testOpacityIsClampedToZeroToOne() {
        let duration = makeProject().rootComposition.duration
        var layer = makeRect(duration: duration)
        layer.opacity.staticValue = 2.5
        XCTAssertEqual(Evaluator.resolve(composition([layer]), frame: 0).layers[0].opacity, 1.0)
        layer.opacity.staticValue = -1
        XCTAssertEqual(Evaluator.resolve(composition([layer]), frame: 0).layers[0].opacity, 0.0)
    }

    func testParentTransformIsApplied() {
        let duration = makeProject().rootComposition.duration
        let parent = Layer(name: "Parent", kind: .null, size: Vec2(x: 100, y: 100), fill: .white,
                           inPoint: .zero, outPoint: duration, position: Vec2(x: 100, y: 0), anchor: Vec2.zero)
        var child = Layer(name: "Child", kind: .solid, size: Vec2(x: 50, y: 50), fill: .white,
                          inPoint: .zero, outPoint: duration, position: Vec2(x: 10, y: 20), anchor: Vec2.zero)
        child.parentID = parent.id
        let frame = Evaluator.resolve(composition([child, parent]), frame: 0)
        XCTAssertEqual(frame.layers.count, 1, "the null parent is not drawn")
        assertEqual(frame.layers[0].transform.applying(to: .zero), Vec2(x: 110, y: 20))
    }

    func testParentLoopDoesNotHang() {
        let duration = makeProject().rootComposition.duration
        var a = makeRect(name: "A", duration: duration)
        var b = makeRect(name: "B", duration: duration)
        a.parentID = b.id
        b.parentID = a.id
        let frame = Evaluator.resolve(composition([a, b]), frame: 0)
        XCTAssertEqual(frame.layers.count, 2)
    }

    func testEffectsAreResolvedAndDisabledOnesSkipped() {
        let duration = makeProject().rootComposition.duration
        var layer = makeRect(duration: duration)
        layer.effects = [
            EffectInstance(effectID: "blur.test", parameters: [
                "radius": .scalar(AnimatedProperty(5.0)),
                "offset": .vector(AnimatedProperty(Vec2(x: 1, y: 2))),
            ]),
            EffectInstance(effectID: "off.test", isEnabled: false),
        ]
        let resolved = Evaluator.resolve(composition([layer]), frame: 0).layers[0].effects
        XCTAssertEqual(resolved.count, 1)
        XCTAssertEqual(resolved[0].effectID, "blur.test")
        XCTAssertEqual(resolved[0].values["radius"], [5.0])
        XCTAssertEqual(resolved[0].values["offset"], [1.0, 2.0])
    }

    func testMotionBlurSamplesAnimatedTransformsBetweenKeyframes() {
        let rate = FrameRate.fps30
        let duration = makeProject().rootComposition.duration
        var layer = makeRect(duration: duration, position: Vec2(x: 0, y: 100))
        layer.position.setKeyframe(at: rate.time(ofFrame: 0), value: Vec2(x: 0, y: 100))
        layer.position.setKeyframe(at: rate.time(ofFrame: 30), value: Vec2(x: 300, y: 100))
        layer.effects = [EffectInstance(effectID: "motion-blur", parameters: [
            "shutterAngle": .scalar(AnimatedProperty(180.0)),
            "samples": .scalar(AnimatedProperty(8.0)),
        ])]
        let frame = Evaluator.resolve(composition([layer]), frame: 15)
        XCTAssertFalse(frame.layers[0].motionBlurTransforms.isEmpty)
        XCTAssertTrue(frame.layers[0].motionBlurTransforms.contains { abs($0.tx - frame.layers[0].transform.tx) > 0.1 })
    }

    func testResolveByTimeReportsTheFrameIndex() {
        let comp = composition([])
        let rate = comp.frameRate
        let frame = Evaluator.resolve(comp, at: rate.time(ofFrame: 3) + Time(ticks: 5))
        XCTAssertEqual(frame.frameIndex, 3)
        XCTAssertEqual(Evaluator.resolve(comp, frame: 3).time, rate.time(ofFrame: 3))
    }

    func testHitTestPicksTopMostLayer() {
        let duration = makeProject().rootComposition.duration
        let bottom = makeRect(name: "Bottom", duration: duration, position: Vec2(x: 500, y: 300))
        let top = makeRect(name: "Top", duration: duration, position: Vec2(x: 550, y: 300))
        let frame = Evaluator.resolve(composition([top, bottom]), frame: 0)
        XCTAssertEqual(Evaluator.hitTest(frame, at: Vec2(x: 500, y: 300)), top.id)
        XCTAssertEqual(Evaluator.hitTest(frame, at: Vec2(x: 420, y: 300)), bottom.id)
        XCTAssertNil(Evaluator.hitTest(frame, at: Vec2(x: 700, y: 300)))
    }

    func testHitTestRespectsEllipseShape() {
        let duration = makeProject().rootComposition.duration
        let circle = Layer(name: "Circle", kind: .shape(.ellipse), size: Vec2(x: 200, y: 200), fill: .white,
                           inPoint: .zero, outPoint: duration, position: Vec2(x: 200, y: 200))
        let frame = Evaluator.resolve(composition([circle]), frame: 0)
        XCTAssertEqual(Evaluator.hitTest(frame, at: Vec2(x: 200, y: 200)), circle.id)
        XCTAssertNil(Evaluator.hitTest(frame, at: Vec2(x: 110, y: 110)), "corner of the box, outside the circle")
    }

    func testHitTestIgnoresFullyTransparentLayers() {
        let duration = makeProject().rootComposition.duration
        var layer = makeRect(duration: duration)
        layer.opacity.staticValue = 0
        let frame = Evaluator.resolve(composition([layer]), frame: 0)
        XCTAssertNil(Evaluator.hitTest(frame, at: Vec2(x: 960, y: 540)))
    }
}
