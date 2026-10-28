import XCTest
@testable import MotionCore

/// Pixel-level tests of connected image processors. Pictures are tiny and deterministic, and expected values were worked
/// out by hand from each effect's definition, not by running the effect.
final class ImageEffectTests: XCTestCase {

    // MARK: Helpers

    private func solid(_ width: Int, _ height: Int, _ r: Float, _ g: Float, _ b: Float, _ a: Float = 1) -> PixelImage {
        PixelImage.filled(width: width, height: height, r: r, g: g, b: b, a: a)
    }

    private func run(_ id: String, _ image: PixelImage, _ settings: [String: [Double]] = [:],
                     scale: Double = 1) -> PixelImage {
        EffectPipeline.apply([ResolvedEffect(effectID: id, values: settings)], to: image, scale: scale).image
    }

    private func expectPixel(_ image: PixelImage, _ x: Int, _ y: Int, _ r: Float, _ g: Float, _ b: Float, _ a: Float = 1,
                             accuracy: Float = 1e-4, file: StaticString = #filePath, line: UInt = #line) {
        let p = image.straight(x, y)
        XCTAssertEqual(p.r, r, accuracy: accuracy, "red at \(x),\(y)", file: file, line: line)
        XCTAssertEqual(p.g, g, accuracy: accuracy, "green at \(x),\(y)", file: file, line: line)
        XCTAssertEqual(p.b, b, accuracy: accuracy, "blue at \(x),\(y)", file: file, line: line)
        XCTAssertEqual(p.a, a, accuracy: accuracy, "alpha at \(x),\(y)", file: file, line: line)
    }

    // MARK: PixelImage itself

    func testPixelImageBasics() {
        var image = PixelImage(width: 2, height: 2)
        XCTAssertEqual(image.pixels.count, 16)
        image.setStraight(1, 0, r: 1, g: 0.5, b: 0, a: 0.5)
        let premultiplied = image.pixel(1, 0)
        XCTAssertEqual(premultiplied.r, 0.5, accuracy: 1e-6)
        XCTAssertEqual(premultiplied.g, 0.25, accuracy: 1e-6)
        let straight = image.straight(1, 0)
        XCTAssertEqual(straight.g, 0.5, accuracy: 1e-6)
        XCTAssertEqual(image.straight(0, 0).a, 0)
    }

    func testPaddingKeepsPixelsAndMovesTheOrigin() {
        let padded = solid(2, 2, 1, 0, 0).padded(by: 3)
        XCTAssertEqual(padded.width, 8)
        XCTAssertEqual(padded.height, 8)
        XCTAssertEqual(padded.originX, -3)
        XCTAssertEqual(padded.originY, -3)
        expectPixel(padded, 3, 3, 1, 0, 0, 1)
        XCTAssertEqual(padded.pixel(0, 0).a, 0)
    }

    func testSamplingIsExactAtPixelCentresAndRepeatsEdges() {
        var image = PixelImage(width: 2, height: 1)
        image.setStraight(0, 0, r: 0, g: 0, b: 0, a: 1)
        image.setStraight(1, 0, r: 1, g: 1, b: 1, a: 1)
        XCTAssertEqual(image.sample(x: 0.5, y: 0.5).r, 0, accuracy: 1e-6)
        XCTAssertEqual(image.sample(x: 1.5, y: 0.5).r, 1, accuracy: 1e-6)
        XCTAssertEqual(image.sample(x: 1.0, y: 0.5).r, 0.5, accuracy: 1e-6)
        XCTAssertEqual(image.sample(x: -50, y: 0.5).r, 0, accuracy: 1e-6, "repeats the edge pixel")
        XCTAssertEqual(image.sample(x: 50, y: 99).r, 1, accuracy: 1e-6)
    }

    func testBlackWhiteUsesLuminanceAndMix() {
        let source = solid(1, 1, 1, 0, 0)
        let result = run("black-white", source)
        let expectedGrey: Float = 0.2126
        expectPixel(result, 0, 0, expectedGrey, expectedGrey, expectedGrey)
    }

    func testSepiaToneWarmsRedPixelAndPreservesAlpha() {
        let source = solid(1, 1, 0.5, 0.25, 0.1, 0.4)
        let result = run("sepia-tone", source)
        let pixel = result.straight(0, 0)
        XCTAssertGreaterThan(pixel.r, pixel.g)
        XCTAssertGreaterThan(pixel.g, pixel.b)
        XCTAssertEqual(pixel.a, 0.4, accuracy: 1e-4)
    }

    func testSolarizeInvertsChannelsAboveThreshold() {
        let result = run("solarize", solid(1, 1, 0.8, 0.2, 0.5), ["threshold": [0.5], "amount": [1]])
        expectPixel(result, 0, 0, 0.2, 0.2, 0.5)
    }

    func testTintMovesChannelsTowardSelectedColour() {
        let result = run("tint", solid(1, 1, 0, 0, 0),
                         ["tintRed": [1], "tintGreen": [0.5], "tintBlue": [0.25], "amount": [0.5]])
        expectPixel(result, 0, 0, 0.5, 0.25, 0.125)
    }

    // MARK: 1. Brightness / Contrast

    func testBrightnessAndContrast() {
        let image = solid(1, 1, 0.75, 0.5, 0.25)
        expectPixel(run("brightness-contrast", image, ["brightness": [0.1]]), 0, 0, 0.85, 0.6, 0.35)
        // contrast 0.5 doubles the distance from middle grey: 0.75 -> 1.0, 0.5 stays, 0.25 -> 0.0
        expectPixel(run("brightness-contrast", image, ["contrast": [0.5]]), 0, 0, 1.0, 0.5, 0.0)
        // contrast -1 shrinks it to a quarter: 0.75 -> 0.5625
        expectPixel(run("brightness-contrast", image, ["contrast": [-1]]), 0, 0, 0.5625, 0.5, 0.4375)
        XCTAssertEqual(run("brightness-contrast", image), image, "default values change nothing")
    }

    func testBrightnessIsClampedAndKeepsAlpha() {
        let image = solid(1, 1, 0.9, 0.2, 0.5, 0.5)
        expectPixel(run("brightness-contrast", image, ["brightness": [1]]), 0, 0, 1, 1, 1, 0.5)
        expectPixel(run("brightness-contrast", image, ["brightness": [-1]]), 0, 0, 0, 0, 0, 0.5)
    }

    // MARK: 2. Hue Shift

    func testHueShiftRotatesTheColourWheel() {
        let red = solid(1, 1, 1, 0, 0)
        expectPixel(run("hue-shift", red, ["degrees": [120]]), 0, 0, 0, 1, 0)
        expectPixel(run("hue-shift", red, ["degrees": [-120]]), 0, 0, 0, 0, 1)
        expectPixel(run("hue-shift", red, ["degrees": [180]]), 0, 0, 0, 1, 1)
        expectPixel(run("hue-shift", solid(1, 1, 0.5, 0.5, 0.5), ["degrees": [90]]), 0, 0, 0.5, 0.5, 0.5)
    }

    func testHueShiftKeepsBrightnessAndAlpha() {
        let result = run("hue-shift", solid(1, 1, 0.8, 0.4, 0.2, 0.5), ["degrees": [60]])
        let p = result.straight(0, 0)
        XCTAssertEqual(max(p.r, p.g, p.b), 0.8, accuracy: 1e-4)
        XCTAssertEqual(p.a, 0.5, accuracy: 1e-6)
    }

    // MARK: 3. Saturation

    func testSaturation() {
        let grey: Float = 0.2126
        expectPixel(run("saturation-vibrance", solid(1, 1, 1, 0, 0), ["saturation": [0]]), 0, 0, grey, grey, grey)
        XCTAssertEqual(run("saturation-vibrance", solid(1, 1, 1, 0, 0)), solid(1, 1, 1, 0, 0), "1 changes nothing")
        // luma of (0.6, 0.4, 0.4) is 0.44252; doubling the distance from it:
        expectPixel(run("saturation-vibrance", solid(1, 1, 0.6, 0.4, 0.4), ["saturation": [2]]), 0, 0, 0.75748, 0.35748, 0.35748)
        // Strong saturation is clamped to a valid colour.
        expectPixel(run("saturation-vibrance", solid(1, 1, 1, 0, 0), ["saturation": [3]]), 0, 0, 1, 0, 0)
        expectPixel(run("saturation-vibrance", solid(1, 1, 1, 0, 0, 0.5), ["saturation": [0]]), 0, 0, grey, grey, grey, 0.5)
    }

    // MARK: 4. Invert

    func testInvertKeepsAlpha() {
        expectPixel(run("invert", solid(1, 1, 0.2, 0.4, 0.6)), 0, 0, 0.8, 0.6, 0.4)
        expectPixel(run("invert", solid(1, 1, 0.2, 0.4, 0.6, 0.5)), 0, 0, 0.8, 0.6, 0.4, 0.5)
        let transparent = PixelImage(width: 1, height: 1)
        XCTAssertEqual(run("invert", transparent), transparent, "a transparent pixel stays transparent")
        let twice = run("invert", run("invert", solid(2, 2, 0.3, 0.6, 0.9, 0.7)))
        expectPixel(twice, 1, 1, 0.3, 0.6, 0.9, 0.7)
    }

    // MARK: Additional colour and geometry effects

    func testColorTemperatureMovesNeutralGreyTowardWarmOrCool() {
        let neutral = solid(1, 1, 0.5, 0.5, 0.5)
        let warm = run("color-temperature", neutral, ["temperature": [1]])
        let cool = run("color-temperature", neutral, ["temperature": [-1]])
        XCTAssertGreaterThan(warm.straight(0, 0).r, neutral.straight(0, 0).r)
        XCTAssertLessThan(warm.straight(0, 0).b, neutral.straight(0, 0).b)
        XCTAssertLessThan(cool.straight(0, 0).r, neutral.straight(0, 0).r)
        XCTAssertGreaterThan(cool.straight(0, 0).b, neutral.straight(0, 0).b)
    }

    func testExposureAddsOneStopAndGammaOneIsNeutral() {
        expectPixel(run("exposure-gamma", solid(1, 1, 0.25, 0.4, 0.5), ["exposure": [1], "gamma": [1]]),
                    0, 0, 0.5, 0.8, 1)
        XCTAssertEqual(run("exposure-gamma", solid(1, 1, 0.2, 0.4, 0.6)), solid(1, 1, 0.2, 0.4, 0.6))
    }

    func testColorizeUsesTintAndPreservesAlpha() {
        let result = run("colorize", solid(1, 1, 0.5, 0.5, 0.5, 0.4),
                         ["tintRed": [1], "tintGreen": [0], "tintBlue": [0], "amount": [1]])
        expectPixel(result, 0, 0, 0.5, 0, 0, 0.4)
    }

    func testFlipLayerAndMirrorTransformPixels() {
        var image = PixelImage(width: 2, height: 1)
        image.setStraight(0, 0, r: 1, g: 0, b: 0, a: 1)
        image.setStraight(1, 0, r: 0, g: 0, b: 1, a: 1)
        let flipped = run("flip-layer", image, ["axis": [0]])
        expectPixel(flipped, 0, 0, 0, 0, 1)
        expectPixel(flipped, 1, 0, 1, 0, 0)
        let mirrored = run("mirror", image, ["axis": [0]])
        expectPixel(mirrored, 0, 0, 1, 0, 0)
        expectPixel(mirrored, 1, 0, 1, 0, 0)
    }

    func testMosaicAveragesEachBlock() {
        var image = PixelImage(width: 2, height: 1)
        image.setStraight(0, 0, r: 1, g: 0, b: 0, a: 1)
        image.setStraight(1, 0, r: 0, g: 0, b: 1, a: 1)
        let result = run("mosaic", image, ["blockSize": [2]])
        expectPixel(result, 0, 0, 0.5, 0, 0.5)
        expectPixel(result, 1, 0, 0.5, 0, 0.5)
    }

    func testFindEdgesProducesVisibleEdgeMap() {
        var image = solid(3, 3, 0, 0, 0)
        image.setStraight(1, 1, r: 1, g: 1, b: 1, a: 1)
        let result = run("find-edges", image)
        XCTAssertGreaterThan(result.straight(1, 0).r, 0)
        XCTAssertEqual(result.straight(1, 0).r, result.straight(1, 0).g, accuracy: 1e-5)
        XCTAssertEqual(result.straight(1, 0).r, result.straight(1, 0).b, accuracy: 1e-5)
    }

    func testChromaticAberrationKeepsCentreGreenAndCanBeDisabled() {
        var image = PixelImage(width: 3, height: 1)
        image.setStraight(0, 0, r: 1, g: 0, b: 0, a: 1)
        image.setStraight(1, 0, r: 0, g: 1, b: 0, a: 1)
        image.setStraight(2, 0, r: 0, g: 0, b: 1, a: 1)
        XCTAssertEqual(run("chromatic-aberration", image, ["offset": [0]]), image)
        let result = run("chromatic-aberration", image, ["offset": [1], "angle": [0], "intensity": [1]])
        XCTAssertGreaterThan(result.straight(1, 0).r, image.straight(1, 0).r)
        XCTAssertGreaterThan(result.straight(1, 0).b, image.straight(1, 0).b)
        XCTAssertEqual(result.straight(1, 0).g, image.straight(1, 0).g, accuracy: 1e-5)
    }

    func testFilmGrainIsDeterministicAndPreservesAlpha() {
        let source = solid(8, 4, 0.5, 0.5, 0.5, 0.4)
        let settings: [String: [Double]] = ["amount": [0.2], "grainSize": [1], "seed": [11]]
        let first = run("film-grain", source, settings)
        let second = run("film-grain", source, settings)
        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, source)
        for y in 0..<first.height {
            for x in 0..<first.width {
                XCTAssertEqual(first.straight(x, y).a, 0.4, accuracy: 1e-5)
            }
        }
    }

    func testScanlinesDarkenRowsWithoutChangingAlpha() {
        let source = solid(2, 4, 1, 1, 1, 0.5)
        let result = run("scanlines", source, ["spacing": [4], "strength": [1], "phase": [0]])
        XCTAssertLessThan(result.straight(0, 0).r, source.straight(0, 0).r)
        XCTAssertGreaterThan(result.straight(0, 2).r, result.straight(0, 0).r)
        XCTAssertEqual(result.straight(0, 0).a, 0.5, accuracy: 1e-5)
    }

    // MARK: 5. Gaussian Blur

    func testBoxSizesApproximatingAGaussian() {
        XCTAssertEqual(ImageEffects.boxRadii(sigma: 3, passes: 3), [2, 2, 3])
    }

    func testBlurOfZeroRadiusIsTheSameImage() {
        let image = solid(5, 5, 0.3, 0.6, 0.9)
        XCTAssertEqual(run("gaussian-blur", image, ["radius": [0]]), image)
    }

    func testBlurOfAFlatPictureChangesNothing() {
        let image = solid(12, 12, 0.3, 0.6, 0.9)
        let blurred = run("gaussian-blur", image, ["radius": [4]])
        for y in [0, 5, 11] { for x in [0, 5, 11] { expectPixel(blurred, x, y, 0.3, 0.6, 0.9, 1, accuracy: 1e-4) } }
    }

    func testBlurSpreadsAnImpulseSymmetricallyWithoutLosingEnergy() {
        var image = PixelImage(width: 41, height: 41)
        image.setPixel(20, 20, r: 1, g: 1, b: 1, a: 1)
        let blurred = run("gaussian-blur", image, ["radius": [3], "edges": [0]])
        let total = (0..<(41 * 41)).reduce(Float(0)) { $0 + blurred.pixels[$1 * 4 + 3] }
        XCTAssertEqual(total, 1, accuracy: 1e-3)
        XCTAssertLessThan(blurred.pixel(20, 20).a, 1)
        XCTAssertGreaterThan(blurred.pixel(21, 20).a, 0)
        XCTAssertEqual(blurred.pixel(23, 20).a, blurred.pixel(17, 20).a, accuracy: 1e-6)
        XCTAssertEqual(blurred.pixel(20, 23).a, blurred.pixel(20, 17).a, accuracy: 1e-6)
    }

    func testBlurEdgeHandling() {
        let image = solid(10, 10, 1, 0, 0)
        let repeated = run("gaussian-blur", image, ["radius": [3], "edges": [1]])
        XCTAssertEqual(repeated.pixel(0, 0).a, 1, accuracy: 1e-5, "repeating edge pixels leaves no transparent border")
        XCTAssertEqual(repeated.pixel(9, 5).a, 1, accuracy: 1e-5)
        let transparent = run("gaussian-blur", image, ["radius": [3], "edges": [0]])
        XCTAssertLessThan(transparent.pixel(0, 0).a, 0.9, "transparent edges fade out at the border")
    }

    func testBlurKeepsAHardEdgeAtThePictureBorder() {
        var image = PixelImage(width: 10, height: 1)
        for x in 0..<10 { image.setStraight(x, 0, r: x < 5 ? 0 : 1, g: 0, b: 0, a: 1) }
        let blurred = run("gaussian-blur", image, ["radius": [2]])
        XCTAssertEqual(blurred.pixel(0, 0).r, 0, accuracy: 0.02)
        XCTAssertEqual(blurred.pixel(9, 0).r, 1, accuracy: 0.02)
        XCTAssertGreaterThan(blurred.pixel(4, 0).r, 0.05, "the middle really is blurred")
    }

    // MARK: 6. Sharpen

    func testSharpenOfAFlatPictureOrZeroAmountChangesNothing() {
        let image = solid(6, 6, 0.4, 0.5, 0.6)
        let flat = run("sharpen", image, ["amount": [2]])
        expectPixel(flat, 3, 3, 0.4, 0.5, 0.6, 1, accuracy: 1e-5)
        XCTAssertEqual(run("sharpen", image, ["amount": [0]]), image)
    }

    func testSharpenRaisesAPeakWithoutLargeHalos() {
        var image = solid(9, 3, 0.5, 0.5, 0.5)
        for y in 0..<3 { image.setStraight(4, y, r: 0.7, g: 0.7, b: 0.7, a: 1) }
        let sharpened = run("sharpen", image, ["amount": [1], "radius": [1]])
        let peak = sharpened.pixel(4, 1).r
        XCTAssertGreaterThan(peak, 0.7, "the line gets crisper")
        XCTAssertLessThanOrEqual(peak, 0.7 + 0.15 * 0.2 + 1e-5, "but only by a limited amount")
        let beside = sharpened.pixel(3, 1).r
        XCTAssertLessThan(beside, 0.5)
        XCTAssertGreaterThanOrEqual(beside, 0.5 - 0.15 * 0.2 - 1e-5)
        XCTAssertEqual(sharpened.pixel(0, 1).r, 0.5, accuracy: 1e-5, "far from the line nothing changes")
        for i in 0..<(9 * 3) { XCTAssertEqual(sharpened.pixels[i * 4 + 3], 1) }
    }

    func testSharpenNeverProducesInvalidOutput() {
        var image = PixelImage(width: 8, height: 8)
        for y in 0..<8 { for x in 0..<8 { image.setStraight(x, y, r: (x + y) % 2 == 0 ? 1 : 0, g: 0.5, b: 0, a: 0.8) } }
        let sharpened = run("sharpen", image, ["amount": [5], "radius": [0.5]])
        for i in 0..<(64) {
            let a = sharpened.pixels[i * 4 + 3]
            for c in 0..<3 {
                let value = sharpened.pixels[i * 4 + c]
                XCTAssertTrue(value >= 0 && value <= a + 1e-6)
            }
        }
    }

    // MARK: 7. Vignette

    func testVignetteDarkensTheCornersAndLeavesTheCentre() {
        let image = solid(101, 101, 1, 1, 1)
        let result = run("vignette", image, ["intensity": [1], "radius": [0.5], "softness": [0]])
        expectPixel(result, 50, 50, 1, 1, 1)
        expectPixel(result, 0, 0, 0, 0, 0)
        expectPixel(result, 100, 100, 0, 0, 0)
    }

    func testVignetteCanLightenAndKeepsAlpha() {
        let image = solid(101, 101, 0, 0, 0, 0.5)
        let result = run("vignette", image, ["intensity": [-1], "radius": [0.5], "softness": [0]])
        expectPixel(result, 50, 50, 0, 0, 0, 0.5)
        expectPixel(result, 0, 0, 1, 1, 1, 0.5)
    }

    func testVignetteSoftnessMakesAGradualFalloff() {
        let image = solid(101, 101, 1, 1, 1)
        let result = run("vignette", image, ["intensity": [1], "radius": [0.7], "softness": [0.5]])
        let centre = result.pixel(50, 50).r
        let middle = result.pixel(90, 50).r
        let corner = result.pixel(0, 0).r
        XCTAssertEqual(centre, 1, accuracy: 1e-5)
        XCTAssertLessThan(corner, middle)
        XCTAssertLessThan(middle, centre)
        XCTAssertEqual(run("vignette", image, ["intensity": [0]]), image)
    }

    func testVignetteCentreCanMove() {
        let image = solid(101, 101, 1, 1, 1)
        let result = run("vignette", image, ["intensity": [1], "radius": [0.3], "softness": [0], "center": [0, 0]])
        expectPixel(result, 0, 0, 1, 1, 1)
        expectPixel(result, 100, 100, 0, 0, 0)
    }

    // MARK: 8. Drop Shadow

    private let hardShadow: [String: [Double]] = ["opacity": [1], "blur": [0], "distance": [3], "angle": [0], "spread": [0]]

    func testDropShadowIsOffsetAndDoesNotCoverTheLayer() {
        let result = run("drop-shadow", solid(4, 4, 1, 0, 0), hardShadow)
        XCTAssertEqual(result.width, 14)
        XCTAssertEqual(result.height, 14)
        XCTAssertEqual(result.originX, -5)
        XCTAssertEqual(result.originY, -5)
        expectPixel(result, 5, 5, 1, 0, 0, 1)            // the layer itself is untouched
        expectPixel(result, 8, 8, 1, 0, 0, 1)
        expectPixel(result, 10, 6, 0, 0, 0, 1)           // shadow to the right, 3 pixels away
        XCTAssertEqual(result.pixel(12, 6).a, 0)         // beyond the shadow
        XCTAssertEqual(result.pixel(4, 6).a, 0)          // nothing on the other side
    }

    func testDropShadowFollowsTheAngle() {
        var settings = hardShadow
        settings["angle"] = [90]                         // straight down
        let result = run("drop-shadow", solid(4, 4, 1, 0, 0), settings)
        XCTAssertEqual(result.pixel(6, 10).a, 1)
        XCTAssertEqual(result.pixel(10, 6).a, 0)
        XCTAssertEqual(result.pixel(6, 4).a, 0)
    }

    func testDropShadowUsesTheLayersAlphaMask() {
        // Only the left half is visible. The right half is transparent and must cast no shadow.
        var image = PixelImage(width: 4, height: 2)
        for y in 0..<2 { for x in 0..<2 { image.setStraight(x, y, r: 1, g: 1, b: 1, a: 1) } }
        var settings = hardShadow
        settings["distance"] = [0]
        settings["spread"] = [0]
        let none = run("drop-shadow", image, settings)
        let margin = -none.originX
        XCTAssertEqual(none.pixel(margin + 3, margin).a, 0, "no shadow under the transparent half")

        var shifted = hardShadow
        shifted["distance"] = [2]
        let result = run("drop-shadow", image, shifted)
        let shiftedMargin = -result.originX
        XCTAssertEqual(result.pixel(shiftedMargin + 3, shiftedMargin).a, 1, accuracy: 1e-6,
                       "shadow lands where the visible half moved to")
    }

    func testDropShadowOfATransparentPictureIsEmpty() {
        let result = run("drop-shadow", PixelImage(width: 3, height: 3), hardShadow)
        XCTAssertTrue(result.pixels.allSatisfy { $0 == 0 })
    }

    func testDropShadowOpacityColourAndSpread() {
        var half = hardShadow
        half["opacity"] = [0.5]
        half["shadowRed"] = [0]
        half["shadowGreen"] = [0]
        half["shadowBlue"] = [1]
        let result = run("drop-shadow", solid(4, 4, 1, 0, 0), half)
        expectPixel(result, 10, 6, 0, 0, 1, 0.5)

        var spread = hardShadow
        spread["spread"] = [1]
        let wider = run("drop-shadow", solid(4, 4, 1, 0, 0), spread)
        let plain = run("drop-shadow", solid(4, 4, 1, 0, 0), hardShadow)
        // The layer's right edge is 4 pixels in. The hard shadow reaches 3 pixels past it; spread adds one more.
        let wideMargin = -wider.originX
        let plainMargin = -plain.originX
        XCTAssertEqual(plain.pixel(plainMargin + 4 + 2, plainMargin + 1).a, 1)
        XCTAssertEqual(plain.pixel(plainMargin + 4 + 3, plainMargin + 1).a, 0)
        XCTAssertEqual(wider.pixel(wideMargin + 4 + 3, wideMargin + 1).a, 1, "spread grows the shadow by one pixel")
    }

    func testDropShadowBlurSoftensTheEdgeAndDistancesScale() {
        var soft = hardShadow
        soft["blur"] = [2]
        let blurred = run("drop-shadow", solid(6, 6, 1, 0, 0), soft)
        let margin = -blurred.originX
        let edge = blurred.pixel(margin + 6 + 3, margin + 3).a      // just beyond the hard shadow edge
        XCTAssertGreaterThan(edge, 0)
        XCTAssertLessThan(edge, 1)

        // A preview made at half size must put the shadow in the same place: 6 layer pixels = 3 bitmap pixels.
        var far = hardShadow
        far["distance"] = [6]
        let half = run("drop-shadow", solid(4, 4, 1, 0, 0), far, scale: 0.5)
        XCTAssertEqual(half.pixel(10, 6).a, 1)
    }

    // MARK: 9. Glow

    private func brightDot() -> PixelImage {
        var image = solid(9, 9, 0, 0, 0)
        image.setStraight(1, 4, r: 1, g: 1, b: 1, a: 1)      // near the left edge
        return image
    }

    func testGlowSpreadsLightAroundBrightPixelsAndGrowsTheCanvas() {
        let result = run("glow", brightDot(), ["threshold": [0.6], "radius": [2], "intensity": [4]])
        XCTAssertEqual(result.width, 25)
        XCTAssertEqual(result.originX, -8)
        // The dot is at picture (1, 4), which is canvas (9, 12) after the 8 pixel border.
        let centre = result.pixel(9, 12)
        XCTAssertEqual(centre.r, 1, accuracy: 1e-5, "the bright pixel stays at full brightness")
        XCTAssertGreaterThan(result.pixel(10, 12).r, 0.05, "its neighbour picked up light")
        XCTAssertGreaterThan(result.pixel(7, 12).a, 0.0001, "light also spills outside the original picture")
    }

    func testGlowKeepsTheOriginalWhereThereIsNoLight() {
        let image = solid(9, 9, 0.2, 0.1, 0.05)               // everything is below the threshold
        let result = run("glow", image, ["threshold": [0.6], "radius": [2], "intensity": [2]])
        expectPixel(result, 8 + 4, 8 + 4, 0.2, 0.1, 0.05)
        XCTAssertEqual(result.pixel(0, 0).a, 0)
    }

    func testGlowOnlyModeLeavesJustTheLight() {
        let result = run("glow", brightDot(), ["threshold": [0.6], "radius": [2], "intensity": [4], "mode": [1]])
        XCTAssertGreaterThan(result.pixel(9, 12).a, 0.05)
        XCTAssertLessThan(result.pixel(9, 12).a, 1)
    }

    func testGlowIsTintedAndZeroIntensityDoesNothing() {
        let tinted = run("glow", brightDot(), ["radius": [2], "intensity": [4], "mode": [1],
                                                 "colorRed": [1], "colorGreen": [0], "colorBlue": [0]])
        let p = tinted.pixel(10, 12)
        XCTAssertGreaterThan(p.r, 0)
        XCTAssertEqual(p.g, 0, accuracy: 1e-6)
        let image = brightDot()
        XCTAssertEqual(run("glow", image, ["intensity": [0]]), image)
    }

    // MARK: 10. Gradient Map

    func testGradientMapUsesTheThreeColours() {
        expectPixel(run("gradient-map", solid(1, 1, 0, 0, 0)), 0, 0, 0.05, 0.05, 0.25)
        expectPixel(run("gradient-map", solid(1, 1, 1, 1, 1)), 0, 0, 1.0, 0.9, 0.4)
        expectPixel(run("gradient-map", solid(1, 1, 0.5, 0.5, 0.5)), 0, 0, 0.8, 0.2, 0.5, 1, accuracy: 1e-3)
        // Halfway between black and the midpoint is halfway between the shadow and midtone colours.
        expectPixel(run("gradient-map", solid(1, 1, 0.25, 0.25, 0.25)), 0, 0, 0.425, 0.125, 0.375, 1, accuracy: 1e-3)
    }

    func testGradientMapKeepsAlphaAndCanMixWithTheOriginal() {
        expectPixel(run("gradient-map", solid(1, 1, 0, 0, 0, 0.4)), 0, 0, 0.05, 0.05, 0.25, 0.4)
        let image = solid(1, 1, 0, 0, 0)
        XCTAssertEqual(run("gradient-map", image, ["mix": [0]]), image)
        expectPixel(run("gradient-map", image, ["mix": [0.5]]), 0, 0, 0.025, 0.025, 0.125)
        XCTAssertEqual(run("gradient-map", PixelImage(width: 1, height: 1)).pixel(0, 0).a, 0)
    }

    // MARK: 11. RGB Split

    private func whiteColumn() -> PixelImage {
        var image = solid(9, 1, 0, 0, 0)
        image.setStraight(3, 0, r: 1, g: 1, b: 1, a: 1)
        return image
    }

    func testRGBSplitMovesRedAndBlueSeparately() {
        let result = run("rgb-split", whiteColumn(), ["redOffset": [2, 0], "blueOffset": [-2, 0]])
        expectPixel(result, 3, 0, 0, 1, 0)         // green stays
        expectPixel(result, 5, 0, 1, 0, 0)         // red moved right by 2
        expectPixel(result, 1, 0, 0, 0, 1)         // blue moved left by 2
        expectPixel(result, 0, 0, 0, 0, 0)
    }

    func testRGBSplitKeepsTheSizeAndLeavesNoTransparentEdges() {
        let result = run("rgb-split", whiteColumn(), ["redOffset": [20, 0], "blueOffset": [-20, 5]])
        XCTAssertEqual(result.width, 9)
        XCTAssertEqual(result.height, 1)
        for x in 0..<9 { XCTAssertEqual(result.pixel(x, 0).a, 1, accuracy: 1e-6) }
    }

    func testRGBSplitVerticalIntensityAndScale() {
        var column = solid(1, 7, 0, 0, 0)
        column.setStraight(0, 2, r: 1, g: 1, b: 1, a: 1)
        let vertical = run("rgb-split", column, ["redOffset": [0, 2], "blueOffset": [0, 0]])
        expectPixel(vertical, 0, 4, 1, 0, 0)

        XCTAssertEqual(run("rgb-split", whiteColumn(), ["redOffset": [2, 0], "intensity": [0]]), whiteColumn())
        // Offsets are in layer pixels: 4 layer pixels at half size is 2 bitmap pixels.
        let halfSize = run("rgb-split", whiteColumn(), ["redOffset": [4, 0], "blueOffset": [0, 0]], scale: 0.5)
        expectPixel(halfSize, 5, 0, 1, 0, 0)
    }

    // MARK: 12. Pixelate

    func testPixelateAveragesEachBlock() {
        var image = PixelImage(width: 4, height: 2)
        let top: [Float] = [0, 0.2, 0.4, 0.6]
        let bottom: [Float] = [0.2, 0.4, 0.6, 0.8]
        for x in 0..<4 {
            image.setStraight(x, 0, r: top[x], g: 0, b: 0, a: 1)
            image.setStraight(x, 1, r: bottom[x], g: 0, b: 0, a: 1)
        }
        let result = run("pixelate", image, ["blockSize": [2]])
        for y in 0..<2 {
            expectPixel(result, 0, y, 0.2, 0, 0)
            expectPixel(result, 1, y, 0.2, 0, 0)
            expectPixel(result, 2, y, 0.6, 0, 0)
            expectPixel(result, 3, y, 0.6, 0, 0)
        }
    }

    func testPixelateEdgeBlocksAlphaAndScale() {
        var image = PixelImage(width: 5, height: 1)
        for x in 0..<5 { image.setStraight(x, 0, r: 1, g: 1, b: 1, a: x == 4 ? 1 : 0) }
        let result = run("pixelate", image, ["blockSize": [2]])
        XCTAssertEqual(result.pixel(0, 0).a, 0)
        XCTAssertEqual(result.pixel(4, 0).a, 1, "a partial block at the edge averages only its own pixels")

        var two = PixelImage(width: 2, height: 1)
        two.setStraight(0, 0, r: 1, g: 1, b: 1, a: 1)
        XCTAssertEqual(run("pixelate", two, ["blockSize": [2]]).pixel(0, 0).a, 0.5, accuracy: 1e-6)

        XCTAssertEqual(run("pixelate", image, ["blockSize": [1]]), image)
        // 4 layer pixels at half size is 2 bitmap pixels, so it matches blockSize 2 at full size.
        XCTAssertEqual(run("pixelate", image, ["blockSize": [4]], scale: 0.5), run("pixelate", image, ["blockSize": [2]]))
    }

    // MARK: 13. Posterize

    func testPosterizeSnapsToEvenlySpacedLevels() {
        let levels: [Double: Float] = [0: 0, 0.1: 0, 0.3: 1.0 / 3, 0.6: 2.0 / 3, 0.99: 1, 1: 1]
        for (input, expected) in levels {
            let result = run("posterize", solid(1, 1, Float(input), 0, 0), ["levels": [4]])
            expectPixel(result, 0, 0, expected, 0, 0, 1, accuracy: 1e-5)
        }
        expectPixel(run("posterize", solid(1, 1, 0.49, 0.5, 0), ["levels": [2]]), 0, 0, 0, 1, 0)
    }

    func testPosterizeRangeAndAlpha() {
        // Levels outside 2...32 are moved back into range instead of producing an invalid picture.
        expectPixel(run("posterize", solid(1, 1, 0.9, 0.2, 0.6), ["levels": [1]]), 0, 0, 1, 0, 1)
        let many = run("posterize", solid(1, 1, 0.5, 0.5, 0.5), ["levels": [100]])
        XCTAssertEqual(many.straight(0, 0).r, 16.0 / 31.0, accuracy: 1e-4)
        expectPixel(run("posterize", solid(1, 1, 0.9, 0.2, 0.6, 0.3), ["levels": [2]]), 0, 0, 1, 0, 1, 0.3)
    }

    // MARK: 14. Directional Blur

    private func impulseRow() -> PixelImage {
        var image = solid(7, 1, 0, 0, 0)
        image.setStraight(3, 0, r: 1, g: 1, b: 1, a: 1)
        return image
    }

    func testDirectionalBlurAveragesAlongTheLine() {
        let result = run("directional-blur", impulseRow(), ["angle": [0], "distance": [2]])
        for x in 2...4 { XCTAssertEqual(result.pixel(x, 0).r, 1.0 / 3, accuracy: 1e-5, "x = \(x)") }
        XCTAssertEqual(result.pixel(1, 0).r, 0, accuracy: 1e-6)
        XCTAssertEqual(result.pixel(5, 0).r, 0, accuracy: 1e-6)
    }

    func testDirectionalBlurFollowsTheAngleAndKeepsEdges() {
        var column = solid(1, 7, 0, 0, 0)
        column.setStraight(0, 3, r: 1, g: 1, b: 1, a: 1)
        let vertical = run("directional-blur", column, ["angle": [90], "distance": [2]])
        for y in 2...4 { XCTAssertEqual(vertical.pixel(0, y).r, 1.0 / 3, accuracy: 1e-5) }

        let flat = solid(6, 6, 0.4, 0.5, 0.6)
        let blurred = run("directional-blur", flat, ["angle": [45], "distance": [10]])
        XCTAssertEqual(blurred.width, 6)
        for x in [0, 5] { for y in [0, 5] { expectPixel(blurred, x, y, 0.4, 0.5, 0.6, 1, accuracy: 1e-4) } }
    }

    func testDirectionalBlurOfZeroDistanceAndScale() {
        XCTAssertEqual(run("directional-blur", impulseRow(), ["distance": [0]]), impulseRow())
        let scaled = run("directional-blur", impulseRow(), ["angle": [0], "distance": [4]], scale: 0.5)
        XCTAssertEqual(scaled, run("directional-blur", impulseRow(), ["angle": [0], "distance": [2]]))
    }

    // MARK: 15. Wave Warp

    private func labelledRows() -> PixelImage {
        // 12 columns with a different red value in each, 20 identical rows.
        var image = PixelImage(width: 12, height: 20)
        for y in 0..<20 { for x in 0..<12 { image.setStraight(x, y, r: Float(x) / 11, g: 0, b: 0, a: 1) } }
        return image
    }

    func testWaveWarpPushesRowsByTheWave() {
        // Square wave, 50 waves per 1000 px = wavelength 20 px. Rows 0...9 are the "up" half, 10...19 the "down" half.
        let settings: [String: [Double]] = ["amplitude": [2], "frequency": [50], "phase": [0], "direction": [0], "waveType": [2]]
        let result = run("wave-warp", labelledRows(), settings)
        XCTAssertEqual(result.width, 12)
        XCTAssertEqual(result.height, 20)
        for y in [0, 5, 9] {
            XCTAssertEqual(result.pixel(5, y).r, Float(3) / 11, accuracy: 1e-5, "row \(y) moved right by 2")
            XCTAssertEqual(result.pixel(0, y).r, 0, accuracy: 1e-5, "left edge repeats")
        }
        for y in [10, 15, 19] {
            XCTAssertEqual(result.pixel(5, y).r, Float(7) / 11, accuracy: 1e-5, "row \(y) moved left by 2")
            XCTAssertEqual(result.pixel(11, y).r, 1, accuracy: 1e-5, "right edge repeats")
        }
    }

    func testWaveWarpNoWaveMeansNoChangeAndOpaqueStaysOpaque() {
        let image = labelledRows()
        XCTAssertEqual(run("wave-warp", image, ["amplitude": [0]]), image)
        XCTAssertEqual(run("wave-warp", image, ["frequency": [0]]), image)
        let sine = run("wave-warp", image, ["amplitude": [3], "frequency": [30], "phase": [40], "direction": [30]])
        XCTAssertEqual(sine.width, 12)
        for i in 0..<(12 * 20) { XCTAssertEqual(sine.pixels[i * 4 + 3], 1, accuracy: 1e-6) }
        let triangle = run("wave-warp", image, ["amplitude": [3], "frequency": [30], "waveType": [1]])
        XCTAssertNotEqual(triangle, image)
    }

    func testWaveWarpIsStableAtDifferentScales() {
        // 20 layer pixels of amplitude at half size is 10 bitmap pixels...
        let image = labelledRows()
        let small = run("wave-warp", image, ["amplitude": [4], "frequency": [25], "waveType": [2]], scale: 0.5)
        let direct = run("wave-warp", image, ["amplitude": [2], "frequency": [50], "waveType": [2]])
        XCTAssertEqual(small, direct, "the same wave expressed in layer pixels gives the same bitmap")
    }
    func testNewlyConnectedEffectsProduceValidResults() {
        var image = PixelImage.filled(width: 12, height: 12, r: 0.1, g: 0.9, b: 0.1, a: 1)
        image.setStraight(6, 6, r: 1, g: 0, b: 0, a: 1)
        let cases: [(String, [String: [Double]])] = [
            ("chroma-key", [:]),
            ("box-blur", ["radius": [2]]),
            ("zoom-blur", ["amount": [18]]),
            ("noise", ["amount": [0.4], "seed": [5]]),
            ("vhs", ["intensity": [0.7], "tracking": [0.5], "scanlines": [0.4],
                     "chromaLoss": [0.4], "noise": [0.2], "tapeMode": [2]]),
            ("cmyk-halftone-dots", ["dotSize": [4]]),
            ("roughen-edges", ["amount": [0.8], "scale": [2]]),
            ("random-displacement", ["horizontal": [2], "vertical": [2], "scale": [3]])
        ]
        for (id, values) in cases {
            let result = EffectPipeline.apply([ResolvedEffect(effectID: id, values: values)], to: image, scale: 1)
            XCTAssertTrue(result.issues.isEmpty, id)
            XCTAssertEqual(result.image.pixels.count, result.image.width * result.image.height * 4, id)
            XCTAssertTrue(result.image.pixels.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 }, id)
        }
        let keyed = EffectPipeline.apply([ResolvedEffect(effectID: "chroma-key", values: [:])], to: image, scale: 1).image
        XCTAssertLessThan(keyed.pixel(0, 0).a, image.pixel(0, 0).a, "green background should become transparent")
    }

}
