import XCTest
@testable import MotionCore

final class ViewportTests: XCTestCase {

    func testPortraitPhoneShowsTheWholeComposition() {
        // A 1920 x 1080 composition in a 390 x 844 view: limited by the width.
        let viewport = Viewport(compWidth: 1920, compHeight: 1080, viewWidth: 390, viewHeight: 844)
        XCTAssertEqual(viewport.scale, 0.203125, accuracy: 1e-9)
        assertEqual(viewport.origin, Vec2(x: 0, y: 312.3125))
        assertEqual(viewport.compToView(Vec2(x: 960, y: 540)), Vec2(x: 195, y: 422))
        assertEqual(viewport.compToView(.zero), viewport.origin)
    }

    func testLandscapePhoneShowsTheWholeComposition() {
        let viewport = Viewport(compWidth: 1920, compHeight: 1080, viewWidth: 844, viewHeight: 390)
        XCTAssertEqual(viewport.scale, 390.0 / 1080.0, accuracy: 1e-9)
        XCTAssertEqual(viewport.origin.y, 0, accuracy: 1e-9)
        XCTAssertEqual(viewport.origin.x, 75.3333333333, accuracy: 1e-6)
        // The far corner of the composition lands on the far edge of the fitted area.
        assertEqual(viewport.compToView(Vec2(x: 1920, y: 1080)), Vec2(x: 844 - 75.3333333333, y: 390), accuracy: 1e-6)
    }

    func testVerticalCompositionInLandscapeView() {
        let viewport = Viewport(compWidth: 1080, compHeight: 1920, viewWidth: 800, viewHeight: 400)
        XCTAssertEqual(viewport.scale, 400.0 / 1920.0, accuracy: 1e-9)
    }

    func testRoundTripBetweenCompositionAndView() {
        let sizes: [(Double, Double)] = [(390, 844), (844, 390), (744, 1133), (1366, 1024)]
        for size in sizes {
            let viewport = Viewport(compWidth: 1920, compHeight: 1080, viewWidth: size.0, viewHeight: size.1,
                                    zoom: 1.7, pan: Vec2(x: 13, y: -9))
            for point in [Vec2.zero, Vec2(x: 960, y: 540), Vec2(x: 1920, y: 1080), Vec2(x: -50, y: 2000)] {
                assertEqual(viewport.viewToComp(viewport.compToView(point)), point, accuracy: 1e-6)
            }
        }
    }

    func testZoomAndPan() {
        let viewport = Viewport(compWidth: 1920, compHeight: 1080, viewWidth: 390, viewHeight: 844,
                                zoom: 2, pan: Vec2(x: 10, y: -20))
        XCTAssertEqual(viewport.scale, 0.40625, accuracy: 1e-9)
        assertEqual(viewport.origin, Vec2(x: -185, y: 182.625))
    }

    func testSameCompositionPixelsOnDifferentScreens() {
        // The composition centre is always the screen centre, whatever the device.
        for size in [(390.0, 844.0), (430.0, 932.0), (1024.0, 1366.0)] {
            let viewport = Viewport(compWidth: 1920, compHeight: 1080, viewWidth: size.0, viewHeight: size.1)
            assertEqual(viewport.compToView(Vec2(x: 960, y: 540)), Vec2(x: size.0 / 2, y: size.1 / 2))
        }
    }

    func testTransformMatchesPointConversion() {
        let viewport = Viewport(compWidth: 1920, compHeight: 1080, viewWidth: 390, viewHeight: 844)
        let point = Vec2(x: 321, y: 123)
        assertEqual(viewport.compToViewTransform.applying(to: point), viewport.compToView(point))
    }

    func testDegenerateSizesDoNotCrash() {
        let viewport = Viewport(compWidth: 0, compHeight: 0, viewWidth: 0, viewHeight: 0)
        XCTAssertEqual(viewport.scale, 1)
    }
}
