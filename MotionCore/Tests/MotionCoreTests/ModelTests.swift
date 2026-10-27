import XCTest
@testable import MotionCore

final class ModelTests: XCTestCase {

    func testNewProjectDurationIsAWholeNumberOfFrames() {
        let at24 = makeProject(frameRate: .fps24, seconds: 5).rootComposition
        XCTAssertEqual(at24.frameCount, 120)
        XCTAssertEqual(at24.duration, Time(ticks: 5 * Time.ticksPerSecond))

        let at2997 = makeProject(frameRate: .fps29_97, seconds: 5).rootComposition
        XCTAssertEqual(at2997.frameCount, 150)
        XCTAssertEqual(at2997.duration.ticks, 150 * 4_708_704)

        let at60 = makeProject(frameRate: .fps60, seconds: 10).rootComposition
        XCTAssertEqual(at60.frameCount, 600)
    }

    func testFrameRateIsIndependentOfCompositionSize() {
        let vertical = Project.makeNew(name: "V", width: 1080, height: 1920, frameRate: .fps25, durationSeconds: 2)
        XCTAssertEqual(vertical.rootComposition.width, 1080)
        XCTAssertEqual(vertical.rootComposition.height, 1920)
        XCTAssertEqual(vertical.rootComposition.frameRate, .fps25)
        XCTAssertEqual(vertical.rootComposition.frameCount, 50)
        assertEqual(vertical.rootComposition.center, Vec2(x: 540, y: 960))
    }

    func testEveryPlannedFrameRateCanBeUsedForAProject() {
        let planned: [FrameRate] = [.fps24, .fps25, .fps30, .fps50, .fps60,
                                    .fps23_976, .fps29_97, .fps59_94, .fps120]
        for rate in planned {
            let comp = makeProject(frameRate: rate, seconds: 2).rootComposition
            XCTAssertGreaterThan(comp.frameCount, 0)
            XCTAssertEqual(comp.frameRate.time(ofFrame: comp.frameCount), comp.duration, "\(rate.displayName)")
        }
    }

    func testLayerDefaults() {
        let layer = Layer(name: "A", kind: .solid, size: Vec2(x: 300, y: 200), fill: .white,
                          inPoint: .zero, outPoint: Time(seconds: 1), position: Vec2(x: 10, y: 20))
        assertEqual(layer.anchor.staticValue, Vec2(x: 150, y: 100))
        assertEqual(layer.scale.staticValue, Vec2(x: 1, y: 1))
        XCTAssertEqual(layer.rotation.staticValue, 0)
        XCTAssertEqual(layer.opacity.staticValue, 1)
        XCTAssertEqual(layer.blendMode, .normal)
        XCTAssertTrue(layer.isVisible)
        XCTAssertTrue(layer.effects.isEmpty)
    }

    func testPropertyKeyKinds() {
        XCTAssertTrue(PropertyKey.position.isVector)
        XCTAssertTrue(PropertyKey.scale.isVector)
        XCTAssertTrue(PropertyKey.anchor.isVector)
        XCTAssertFalse(PropertyKey.rotation.isVector)
        XCTAssertFalse(PropertyKey.opacity.isVector)
    }

    func testKeyframeTimesAreSortedAndUnique() {
        var layer = makeRect(duration: Time(seconds: 5))
        let rate = FrameRate.fps30
        layer.position.setKeyframe(at: rate.time(ofFrame: 30), value: .zero)
        layer.position.setKeyframe(at: rate.time(ofFrame: 0), value: .zero)
        layer.opacity.setKeyframe(at: rate.time(ofFrame: 30), value: 1)
        layer.opacity.setKeyframe(at: rate.time(ofFrame: 10), value: 0)
        XCTAssertEqual(layer.keyframeTimes, [rate.time(ofFrame: 0), rate.time(ofFrame: 10), rate.time(ofFrame: 30)])
    }

    func testPresetsContainThePlannedFrameRates() {
        let rates = FrameRateOption.all.map { $0.rate }
        for expected in [FrameRate.fps24, .fps25, .fps30, .fps50, .fps60, .fps23_976, .fps29_97, .fps59_94] {
            XCTAssertTrue(rates.contains(expected), expected.displayName)
        }
        XCTAssertFalse(ResolutionPreset.all.isEmpty)
    }

    func testDemoProject() throws {
        let project = SampleProjects.demo()
        let comp = project.rootComposition
        XCTAssertEqual(comp.frameRate, .fps29_97)
        XCTAssertEqual(comp.layers.count, 3)
        XCTAssertEqual(comp.frameCount, 150)

        // The circle fades in over its first 30 frames and slides right.
        XCTAssertEqual(Evaluator.resolve(comp, frame: 0).layers.count, 2, "square starts at frame 15")
        XCTAssertEqual(Evaluator.resolve(comp, frame: 15).layers.count, 3)
        let circle = try XCTUnwrap(comp.layers.first(where: { $0.name == "Circle" }))
        let rate = comp.frameRate
        XCTAssertEqual(circle.opacity.value(at: rate.time(ofFrame: 0)), 0, accuracy: 1e-9)
        XCTAssertEqual(circle.opacity.value(at: rate.time(ofFrame: 30)), 1, accuracy: 1e-9)
        assertEqual(circle.position.value(at: rate.time(ofFrame: 149)), Vec2(x: 1360, y: 540))
    }
}
