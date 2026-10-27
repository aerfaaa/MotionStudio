import XCTest
@testable import MotionCore

final class PersistenceTests: XCTestCase {

    private func jsonObject(_ project: Project) throws -> [String: Any] {
        let data = try ProjectFile.encode(project)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func data(from object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    private func assertCorrupt(_ data: Data, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try ProjectFile.decode(data), file: file, line: line) { error in
            guard let fileError = error as? ProjectFileError, case .corrupt = fileError else {
                return XCTFail("Expected a corrupt-file error, got \(error)", file: file, line: line)
            }
        }
    }

    func testRoundTripInMemory() throws {
        let project = SampleProjects.demo()
        let decoded = try ProjectFile.decode(ProjectFile.encode(project))
        XCTAssertEqual(decoded, project)
    }

    func testEncodingIsStable() throws {
        let project = SampleProjects.demo()
        XCTAssertEqual(try ProjectFile.encode(project), try ProjectFile.encode(project))
    }

    func testFrameRateIsSavedAsAFraction() throws {
        let object = try jsonObject(SampleProjects.demo())
        let compositions = try XCTUnwrap(object["compositions"] as? [[String: Any]])
        let frameRate = try XCTUnwrap(compositions[0]["frameRate"] as? [String: Any])
        XCTAssertEqual(frameRate["numerator"] as? Int, 30000)
        XCTAssertEqual(frameRate["denominator"] as? Int, 1001)
    }

    func testSaveAndLoadFolder() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).motionproj", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let project = SampleProjects.demo()
        try ProjectFile.save(project, toFolder: folder)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("project.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("media").path))
        XCTAssertEqual(try ProjectFile.load(fromFolder: folder), project)

        // Saving again over an existing project works too.
        var changed = project
        changed.name = "Renamed"
        try ProjectFile.save(changed, toFolder: folder)
        XCTAssertEqual(try ProjectFile.load(fromFolder: folder).name, "Renamed")
    }

    func testMissingFolderReportsNotFound() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).motionproj")
        XCTAssertThrowsError(try ProjectFile.load(fromFolder: folder)) {
            XCTAssertEqual($0 as? ProjectFileError, .notFound)
        }
    }

    func testNewerFormatIsRejectedWithAClearError() throws {
        var object = try jsonObject(SampleProjects.demo())
        object["schemaVersion"] = 999
        XCTAssertThrowsError(try ProjectFile.decode(try data(from: object))) {
            XCTAssertEqual($0 as? ProjectFileError, .newerThanApp(found: 999, supported: Project.currentSchemaVersion))
        }
    }

    func testGarbageIsRejected() {
        assertCorrupt(Data("this is not json".utf8))
        assertCorrupt(Data("{}".utf8))
        assertCorrupt(Data(#"{"schemaVersion":0}"#.utf8))
    }

    func testInvalidFrameRateIsRejected() throws {
        var object = try jsonObject(SampleProjects.demo())
        var compositions = try XCTUnwrap(object["compositions"] as? [[String: Any]])
        var frameRate = try XCTUnwrap(compositions[0]["frameRate"] as? [String: Any])
        frameRate["denominator"] = 0
        compositions[0]["frameRate"] = frameRate
        object["compositions"] = compositions
        assertCorrupt(try data(from: object))
    }

    func testInvalidCompositionSizeIsRejected() throws {
        var project = SampleProjects.demo()
        try project.updateComposition(project.rootCompositionID) { $0.width = 0 }
        assertCorrupt(try ProjectFile.encode(project))
    }

    func testProjectWithoutCompositionsIsRejected() throws {
        var object = try jsonObject(SampleProjects.demo())
        object["compositions"] = [[String: Any]]()
        assertCorrupt(try data(from: object))
    }

    func testFieldsAddedAfterVersionOneAreOptionalWhenOpening() throws {
        var object = try jsonObject(SampleProjects.demo())
        var compositions = try XCTUnwrap(object["compositions"] as? [[String: Any]])
        var layers = try XCTUnwrap(compositions[0]["layers"] as? [[String: Any]])
        for index in layers.indices {
            for key in ["blendMode", "parentID", "isVisible", "effects"] {
                layers[index].removeValue(forKey: key)
            }
        }
        compositions[0]["layers"] = layers
        object["compositions"] = compositions

        let project = try ProjectFile.decode(try data(from: object))
        let layer = project.rootComposition.layers[0]
        XCTAssertEqual(layer.blendMode, .normal)
        XCTAssertTrue(layer.isVisible)
        XCTAssertTrue(layer.effects.isEmpty)
        XCTAssertNil(layer.parentID)
    }

    func testEffectsSurviveSaving() throws {
        var project = SampleProjects.demo()
        try project.updateLayer(project.rootCompositionID, project.rootComposition.layers[0].id) { layer in
            layer.effects = [EffectInstance(effectID: "blur.test", parameters: [
                "radius": .scalar(AnimatedProperty(3.0)),
                "centre": .vector(AnimatedProperty(Vec2(x: 1, y: 2))),
            ])]
            layer.blendMode = .screen
        }
        let decoded = try ProjectFile.decode(ProjectFile.encode(project))
        XCTAssertEqual(decoded, project)
        XCTAssertEqual(decoded.rootComposition.layers[0].blendMode, .screen)
    }
    func testVideoAudioTextAndFontFieldsSurviveProjectRoundTrip() throws {
        var project = SampleProjects.demo()
        let compID = project.rootCompositionID
        let duration = project.rootComposition.duration
        let videoID = UUID()
        let audioID = UUID()
        let video = Layer(name: "Footage", kind: .video(assetID: videoID),
                          size: Vec2(x: 640, y: 360), fill: .white,
                          inPoint: .zero, outPoint: duration, position: project.rootComposition.center)
        let audio = Layer(name: "Sound", kind: .audio(assetID: audioID),
                          size: Vec2(x: 1920, y: 1), fill: .white,
                          inPoint: .zero, outPoint: duration, position: project.rootComposition.center)
        let text = Layer(name: "Title", kind: .text("Hello"), textFontName: "Example-Regular",
                         size: Vec2(x: 500, y: 100), fill: .white,
                         inPoint: .zero, outPoint: duration, position: project.rootComposition.center)
        try project.updateComposition(compID) { composition in
            composition.layers.append(contentsOf: [video, audio, text])
        }
        let decoded = try ProjectFile.decode(ProjectFile.encode(project))
        let layers = decoded.rootComposition.layers
        XCTAssertTrue(layers.contains { $0.kind == .video(assetID: videoID) })
        XCTAssertTrue(layers.contains { $0.kind == .audio(assetID: audioID) })
        let decodedText = try XCTUnwrap(layers.first { $0.name == "Title" })
        XCTAssertEqual(decodedText.kind, .text("Hello"))
        XCTAssertEqual(decodedText.textFontName, "Example-Regular")
    }

}
