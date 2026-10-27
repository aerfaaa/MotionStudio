import XCTest
@testable import MotionCore

final class CompositionSettingsTests: XCTestCase {

    private func setUpDocument() throws -> (doc: Document, compID: UUID, layer: Layer) {
        let project = makeProject(frameRate: .fps30, seconds: 5)
        let layer = makeRect(duration: project.rootComposition.duration, position: Vec2(x: 400, y: 300))
        let doc = Document(project: project)
        try doc.perform(AddLayer(compositionID: project.rootCompositionID, layer: layer))
        return (doc, project.rootCompositionID, layer)
    }

    func testChangingTheCanvasSizeDoesNotStretchArtwork() throws {
        let (doc, compID, layer) = try setUpDocument()
        try doc.perform(SetCompositionSettings(compositionID: compID, width: 1080, height: 1920,
                                               frameRate: .fps30, durationSeconds: 5))
        let comp = doc.project.rootComposition
        XCTAssertEqual(comp.width, 1080)
        XCTAssertEqual(comp.height, 1920)
        let after = try XCTUnwrap(comp.layer(withID: layer.id))
        XCTAssertEqual(after.size, layer.size)
        XCTAssertEqual(after.position, layer.position)
        XCTAssertEqual(after.scale, layer.scale)
    }

    func testChangingTheFrameRateKeepsTheLengthAsWholeFrames() throws {
        let (doc, compID, _) = try setUpDocument()
        try doc.perform(SetCompositionSettings(compositionID: compID, width: 1920, height: 1080,
                                               frameRate: .fps29_97, durationSeconds: 5))
        let comp = doc.project.rootComposition
        XCTAssertEqual(comp.frameCount, 150)
        XCTAssertEqual(comp.duration.ticks, 150 * 4_708_704)
    }

    func testLayersThatEndedAtTheOldEndFollowTheNewEnd() throws {
        let (doc, compID, layer) = try setUpDocument()
        try doc.perform(SetCompositionSettings(compositionID: compID, width: 1920, height: 1080,
                                               frameRate: .fps30, durationSeconds: 10))
        let comp = doc.project.rootComposition
        XCTAssertEqual(comp.frameCount, 300)
        XCTAssertEqual(comp.layer(withID: layer.id)?.outPoint, comp.duration)
    }

    func testInvalidSettingsAreRefused() throws {
        let (doc, compID, _) = try setUpDocument()
        let before = doc.project
        let bad: [(Int, Int, Double)] = [(0, 1080, 5), (1920, 8, 5), (20000, 1080, 5), (1920, 1080, 0), (1920, 1080, -3)]
        for entry in bad {
            XCTAssertThrowsError(try doc.perform(SetCompositionSettings(
                compositionID: compID, width: entry.0, height: entry.1, frameRate: .fps30, durationSeconds: entry.2))) {
                XCTAssertEqual($0 as? EditError, .invalidValue)
            }
        }
        XCTAssertEqual(doc.project, before)
    }

    func testCompositionSettingsAreUndoable() throws {
        let (doc, compID, _) = try setUpDocument()
        let before = doc.project
        try doc.perform(SetCompositionSettings(compositionID: compID, width: 1080, height: 1350,
                                               frameRate: .fps60, durationSeconds: 3))
        XCTAssertEqual(doc.project.rootComposition.frameCount, 180)
        doc.undo()
        XCTAssertEqual(doc.project, before)
    }

    func testAspectRatioPresetsFromTheSpecification() {
        func ratio(_ preset: ResolutionPreset) -> Double { Double(preset.width) / Double(preset.height) }
        let labels = ResolutionPreset.all.map { $0.label }
        XCTAssertTrue(labels.contains(where: { $0.hasPrefix("9:16") }))
        XCTAssertTrue(labels.contains(where: { $0.hasPrefix("16:9") }))
        XCTAssertTrue(labels.contains(where: { $0.hasPrefix("1:1") }))
        XCTAssertTrue(labels.contains(where: { $0.hasPrefix("4:5") }))
        XCTAssertTrue(labels.contains(where: { $0.hasPrefix("3:4") }))
        for preset in ResolutionPreset.all {
            if preset.label.hasPrefix("9:16") { XCTAssertEqual(ratio(preset), 9.0 / 16.0, accuracy: 0.001) }
            if preset.label.hasPrefix("4:5") { XCTAssertEqual(ratio(preset), 4.0 / 5.0, accuracy: 0.001) }
            if preset.label.hasPrefix("3:4") { XCTAssertEqual(ratio(preset), 3.0 / 4.0, accuracy: 0.001) }
            if preset.label.hasPrefix("1:1") { XCTAssertEqual(ratio(preset), 1.0, accuracy: 0.001) }
        }
        XCTAssertEqual(Set(ResolutionPreset.all.map { $0.id }).count, ResolutionPreset.all.count)
    }

    func testCustomSizeRoundTrips() throws {
        let project = Project.makeNew(name: "Custom", width: 1234, height: 777, frameRate: .fps50, durationSeconds: 2)
        let reloaded = try ProjectFile.decode(ProjectFile.encode(project))
        XCTAssertEqual(reloaded.rootComposition.width, 1234)
        XCTAssertEqual(reloaded.rootComposition.height, 777)
        XCTAssertEqual(reloaded.rootComposition.frameCount, 100)
    }
}
