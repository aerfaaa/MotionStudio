import XCTest
@testable import MotionCore

final class EffectPipelineTests: XCTestCase {

    private func resolved(_ id: String, _ values: [String: [Double]] = [:]) -> ResolvedEffect {
        ResolvedEffect(effectID: id, values: values)
    }

    private func grey(_ value: Float) -> PixelImage {
        PixelImage.filled(width: 2, height: 2, r: value, g: value, b: value)
    }

    func testMotionBlurIsTransformBasedAndDoesNotBlurAStaticSourceBitmap() {
        let image = PixelImage.filled(width: 5, height: 1, r: 0, g: 0, b: 0)
        var source = image
        source.setStraight(2, 0, r: 1, g: 1, b: 1, a: 1)
        let result = EffectPipeline.apply([resolved("motion-blur", ["shutterAngle": [180], "samples": [8]])],
                                          to: source, scale: 1)
        XCTAssertEqual(result.image, source, "Motion blur should be generated from changing transforms, not baked into a static bitmap.")
        XCTAssertTrue(result.issues.isEmpty)
        XCTAssertFalse(EffectPipeline.hasWork([resolved("motion-blur")]))
    }

    func testEffectsRunInOrderAndOrderChangesTheResult() {
        let brighten = resolved("brightness-contrast", ["brightness": [0.5]])
        let invert = resolved("invert")
        // 0.25 brightened is 0.75, inverted is 0.25.
        let brightenThenInvert = EffectPipeline.apply([brighten, invert], to: grey(0.25), scale: 1).image
        // 0.25 inverted is 0.75, brightened is clamped to 1.0.
        let invertThenBrighten = EffectPipeline.apply([invert, brighten], to: grey(0.25), scale: 1).image
        XCTAssertEqual(brightenThenInvert.straight(0, 0).r, 0.25, accuracy: 1e-5)
        XCTAssertEqual(invertThenBrighten.straight(0, 0).r, 1.0, accuracy: 1e-5)
        XCTAssertNotEqual(brightenThenInvert, invertThenBrighten)
    }

    func testTheSameEffectCanBeStackedTwice() {
        let invert = resolved("invert")
        let twice = EffectPipeline.apply([invert, invert], to: grey(0.3), scale: 1).image
        XCTAssertEqual(twice.straight(1, 1).r, 0.3, accuracy: 1e-5)
    }

    func testAnEmptyStackReturnsTheSamePicture() {
        let image = grey(0.4)
        let result = EffectPipeline.apply([], to: image, scale: 1)
        XCTAssertEqual(result.image, image)
        XCTAssertTrue(result.issues.isEmpty)
        XCTAssertFalse(EffectPipeline.hasWork([]))
    }

    func testUnknownAndUnimplementedEffectsAreSkippedWithAMessage() {
        let image = grey(0.4)
        let result = EffectPipeline.apply([resolved("not-a-real-effect"), resolved("displacement-map"), resolved("invert")],
                                          to: image, scale: 1)
        XCTAssertEqual(result.image.straight(0, 0).r, 0.6, accuracy: 1e-5, "the valid effect still ran")
        XCTAssertEqual(result.issues.count, 1)
        XCTAssertEqual(result.issues[0].effectID, "not-a-real-effect")
        XCTAssertTrue(result.issues[0].message.contains("Unknown"))
        XCTAssertTrue(EffectPipeline.hasWork([resolved("invert")]))
        XCTAssertTrue(EffectPipeline.hasWork([resolved("displacement-map"), resolved("nope")]))
    }

    func testInvalidScaleIsReportedAndThePictureKept() {
        let image = grey(0.4)
        for scale in [0.0, -1.0, Double.nan, Double.infinity] {
            let result = EffectPipeline.apply([resolved("invert")], to: image, scale: scale)
            XCTAssertEqual(result.image, image)
            XCTAssertEqual(result.issues.count, 1)
        }
    }

    func testSettingsAreValidatedBeforeUse() {
        let blur = EffectRegistry.definition(id: "gaussian-blur")
        XCTAssertEqual(EffectValues(values: ["radius": [9999]], definition: blur).scalar("radius"), 250)
        XCTAssertEqual(EffectValues(values: ["radius": [-5]], definition: blur).scalar("radius"), 0)
        XCTAssertEqual(EffectValues(values: ["radius": [.nan]], definition: blur).scalar("radius"), 10, "damaged value gives the default")
        XCTAssertEqual(EffectValues(values: ["radius": [1, 2]], definition: blur).scalar("radius"), 10, "wrong count gives the default")
        XCTAssertEqual(EffectValues(values: [:], definition: blur).scalar("radius"), 10, "missing gives the default")
        XCTAssertEqual(EffectValues(values: ["quality": [7]], definition: blur).choice("quality"), 2)
        XCTAssertEqual(EffectValues(values: [:], definition: blur).choice("edges"), 1, "repeat edge pixels by default")
        let split = EffectRegistry.definition(id: "rgb-split")
        XCTAssertEqual(EffectValues(values: ["redOffset": [1]], definition: split).vector("redOffset"), Vec2(x: -8, y: 0))
        XCTAssertEqual(EffectValues(values: ["redOffset": [99999, -99999]], definition: split).vector("redOffset"), Vec2(x: 10000, y: -10000))
        XCTAssertEqual(EffectValues(values: ["unknown": [1]], definition: blur).scalar("unknown"), 0, "unknown names are ignored")
    }

    func testDefaultsGiveSaneResultsForEveryAvailableEffect() {
        var image = PixelImage.filled(width: 16, height: 16, r: 0.6, g: 0.4, b: 0.2, a: 0.9)
        image.setStraight(8, 8, r: 1, g: 1, b: 1, a: 1)
        for id in ImageEffects.availableIDs {
            let result = EffectPipeline.apply([ResolvedEffect(effectID: id, values: [:])], to: image, scale: 1)
            XCTAssertTrue(result.issues.isEmpty, id)
            XCTAssertEqual(result.image.pixels.count, result.image.width * result.image.height * 4, id)
            for value in result.image.pixels {
                XCTAssertTrue(value.isFinite && value >= -1e-5 && value <= 1 + 1e-5, "\(id) produced \(value)")
            }
            for i in 0..<(result.image.width * result.image.height) {
                let a = result.image.pixels[i * 4 + 3]
                for c in 0..<3 { XCTAssertLessThanOrEqual(result.image.pixels[i * 4 + c], a + 1e-5, "\(id): colour above alpha") }
            }
        }
    }

    func testExtremeSettingsStayValid() {
        let image = PixelImage.filled(width: 12, height: 12, r: 0.5, g: 0.5, b: 0.5)
        let extremes: [(String, [String: [Double]])] = [
            ("gaussian-blur", ["radius": [250]]),
            ("sharpen", ["amount": [5], "radius": [20]]),
            ("drop-shadow", ["blur": [60], "distance": [300], "spread": [40]]),
            ("glow", ["radius": [100], "intensity": [4], "threshold": [0]]),
            ("directional-blur", ["distance": [500], "angle": [123]]),
            ("wave-warp", ["amplitude": [500], "frequency": [50]]),
            ("pixelate", ["blockSize": [200]]),
            ("rgb-split", ["redOffset": [10000, 10000], "blueOffset": [-10000, -10000]]),
        ]
        for (id, settings) in extremes {
            let result = EffectPipeline.apply([ResolvedEffect(effectID: id, values: settings)], to: image, scale: 1)
            XCTAssertTrue(result.issues.isEmpty, id)
            XCTAssertTrue(result.image.pixels.allSatisfy { $0.isFinite }, id)
            XCTAssertLessThanOrEqual(result.image.width, 12 + 2 * ImageEffects.maximumMargin, "\(id): canvas growth is capped")
        }
    }

    func testCanvasGrowthAddsUpAcrossTheStack() {
        let image = PixelImage.filled(width: 6, height: 6, r: 1, g: 0, b: 0)
        let shadow = ResolvedEffect(effectID: "drop-shadow", values: ["blur": [0], "distance": [3], "angle": [0], "spread": [0]])
        let afterShadow = EffectPipeline.apply([shadow], to: image, scale: 1).image
        XCTAssertEqual(afterShadow.originX, -5)
        let glow = ResolvedEffect(effectID: "glow", values: ["radius": [2], "intensity": [1]])
        let both = EffectPipeline.apply([shadow, glow], to: image, scale: 1).image
        XCTAssertLessThan(both.originX, afterShadow.originX, "the glow grew the canvas again")
        XCTAssertEqual(both.width, 6 + 2 * (-both.originX))
    }

    func testEmptyPicturesDoNotCrash() {
        let empty = PixelImage(width: 0, height: 0)
        for id in ImageEffects.availableIDs {
            let result = EffectPipeline.apply([ResolvedEffect(effectID: id, values: [:])], to: empty, scale: 1)
            XCTAssertTrue(result.image.isEmpty, id)
        }
    }

    func testAnimatedSettingsFlowThroughTheEvaluator() throws {
        // An effect setting with keyframes is resolved at the frame being drawn, then processed.
        var project = Project.makeNew(name: "T", frameRate: .fps30, durationSeconds: 2)
        let comp = project.rootComposition
        let asset = Asset(kind: .image, displayName: "a.png", relativePath: "media/a.png", pixelSize: Vec2(x: 100, y: 100))
        var layer = try XCTUnwrap(ImageLayerFactory.makeLayer(for: asset, in: comp))
        var effect = try XCTUnwrap(EffectRegistry.makeInstance(id: "brightness-contrast"))
        let rate = FrameRate.fps30
        var track = AnimatedProperty(0.0)
        track.setKeyframe(at: rate.time(ofFrame: 0), value: 0)
        track.setKeyframe(at: rate.time(ofFrame: 30), value: 1)
        effect.parameters["brightness"] = .scalar(track)
        layer.effects = [effect]
        try project.updateComposition(project.rootCompositionID) { $0.layers = [layer] }
        let frame15 = Evaluator.resolve(project.rootComposition, frame: 15)
        let resolvedEffect = try XCTUnwrap(frame15.layers.first?.effects.first)
        XCTAssertEqual(resolvedEffect.values["brightness"]?.first ?? -1, 0.5, accuracy: 1e-9)
        let result = EffectPipeline.apply([resolvedEffect], to: PixelImage.filled(width: 1, height: 1, r: 0.2, g: 0.2, b: 0.2), scale: 1)
        XCTAssertEqual(result.image.straight(0, 0).r, 0.7, accuracy: 1e-5)
    }
}
