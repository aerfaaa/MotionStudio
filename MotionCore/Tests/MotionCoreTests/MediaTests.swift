import XCTest
@testable import MotionCore

final class MediaTests: XCTestCase {

    private func temporaryProjectFolder() -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).motionproj", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func testImportingDataStoresAFileInsideTheProject() throws {
        let folder = temporaryProjectFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = try ProjectMedia.importData(Data([1, 2, 3]), fileExtension: "PNG", baseName: "My Photo", intoProjectFolder: folder)
        XCTAssertTrue(path.hasPrefix("media/"))
        XCTAssertTrue(path.hasSuffix("-My Photo.png"), path)
        let asset = Asset(kind: .image, displayName: "My Photo", relativePath: path)
        let url = try XCTUnwrap(ProjectMedia.fileURL(for: asset, inProjectFolder: folder))
        XCTAssertEqual(try Data(contentsOf: url), Data([1, 2, 3]))
        XCTAssertTrue(ProjectMedia.fileExists(for: asset, inProjectFolder: folder))
    }

    func testSameNameTwiceGivesTwoFiles() throws {
        let folder = temporaryProjectFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let a = try ProjectMedia.importData(Data([1]), fileExtension: "jpg", baseName: "photo", intoProjectFolder: folder)
        let b = try ProjectMedia.importData(Data([2]), fileExtension: "jpg", baseName: "photo", intoProjectFolder: folder)
        XCTAssertNotEqual(a, b)
    }

    func testFileNamesAreMadeSafe() throws {
        XCTAssertEqual(ProjectMedia.safeFileName("../../evil"), "---evil")
        XCTAssertFalse(ProjectMedia.safeFileName("a..b").contains(".."))
        XCTAssertEqual(ProjectMedia.safeFileName("a/b:c"), "a-b-c")
        XCTAssertEqual(ProjectMedia.safeFileName("   "), "media")
        XCTAssertEqual(ProjectMedia.safeFileName(String(repeating: "x", count: 200)).count, 60)
        let folder = temporaryProjectFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = try ProjectMedia.importData(Data([1]), fileExtension: "../x", baseName: "../../etc/passwd", intoProjectFolder: folder)
        XCTAssertEqual(path.split(separator: "/").count, 2, "stays directly inside media/")
        XCTAssertFalse(path.contains(".."))
    }

    func testImportedFilesSurviveWhenTheOriginalIsDeleted() throws {
        let folder = temporaryProjectFolder()
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jpg")
        try Data([9, 9, 9]).write(to: source)
        defer { try? FileManager.default.removeItem(at: folder); try? FileManager.default.removeItem(at: source) }
        let path = try ProjectMedia.importFile(at: source, intoProjectFolder: folder)
        try FileManager.default.removeItem(at: source)
        let asset = Asset(kind: .image, displayName: "x", relativePath: path)
        XCTAssertTrue(ProjectMedia.fileExists(for: asset, inProjectFolder: folder), "the project has its own copy")
        XCTAssertTrue(path.hasSuffix(".jpg"))
    }

    func testImportingAMissingFileFailsCleanly() {
        let folder = temporaryProjectFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
        XCTAssertThrowsError(try ProjectMedia.importFile(at: missing, intoProjectFolder: folder)) { error in
            guard case MediaError.copyFailed = error else { return XCTFail("expected copyFailed, got \(error)") }
        }
    }

    func testUnsafeStoredPathsAreRefused() {
        let folder = URL(fileURLWithPath: "/tmp/project.motionproj")
        for path in ["../x.png", "media/../x.png", "/etc/passwd", "media/sub/x.png", "media\\x.png", "media/", "other/x.png", "x.png", ""] {
            let asset = Asset(kind: .image, displayName: "x", relativePath: path)
            XCTAssertNil(ProjectMedia.fileURL(for: asset, inProjectFolder: folder), "should refuse \(path)")
            XCTAssertFalse(ProjectMedia.fileExists(for: asset, inProjectFolder: folder))
        }
        XCTAssertNotNil(ProjectMedia.fileURL(for: Asset(kind: .image, displayName: "x", relativePath: "media/abc.png"), inProjectFolder: folder))
    }

    func testMissingAssetsAreReported() throws {
        let folder = temporaryProjectFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = try ProjectMedia.importData(Data([1]), fileExtension: "png", baseName: "here", intoProjectFolder: folder)
        let present = Asset(kind: .image, displayName: "here", relativePath: path)
        let gone = Asset(kind: .image, displayName: "gone", relativePath: "media/gone.png")
        let bad = Asset(kind: .image, displayName: "bad", relativePath: "../bad.png")
        var project = makeProject()
        project.assets = [present, gone, bad]
        XCTAssertEqual(Set(ProjectMedia.missingAssets(in: project, folder: folder).map { $0.displayName }), ["gone", "bad"])
    }

    func testImageLayersFitTheCompositionKeepingTheAspectRatio() throws {
        let comp = makeProject().rootComposition                    // 1920 x 1080
        let landscape = try XCTUnwrap(ImageLayerFactory.fittedSize(pixelSize: Vec2(x: 4000, y: 3000), in: comp))
        XCTAssertEqual(landscape.x, 1152, accuracy: 1e-9)
        XCTAssertEqual(landscape.y, 864, accuracy: 1e-9)
        let portrait = try XCTUnwrap(ImageLayerFactory.fittedSize(pixelSize: Vec2(x: 3000, y: 4000), in: comp))
        XCTAssertEqual(portrait.x, 648, accuracy: 1e-9)
        XCTAssertEqual(portrait.y, 864, accuracy: 1e-9)
        XCTAssertEqual(landscape.x / landscape.y, 4.0 / 3.0, accuracy: 1e-9)
        XCTAssertNil(ImageLayerFactory.fittedSize(pixelSize: Vec2(x: 0, y: 100), in: comp))
        XCTAssertNil(ImageLayerFactory.fittedSize(pixelSize: Vec2(x: .nan, y: 100), in: comp))
    }

    func testMakingAnImageLayer() throws {
        let comp = makeProject().rootComposition
        let asset = Asset(kind: .image, displayName: "Holiday.jpg", relativePath: "media/a.jpg", pixelSize: Vec2(x: 1000, y: 500))
        let layer = try XCTUnwrap(ImageLayerFactory.makeLayer(for: asset, in: comp))
        XCTAssertEqual(layer.name, "Holiday")
        XCTAssertEqual(layer.kind, .image(assetID: asset.id))
        XCTAssertEqual(layer.position.staticValue, comp.center)
        XCTAssertEqual(layer.outPoint, comp.duration)
        XCTAssertEqual(layer.size.x / layer.size.y, 2, accuracy: 1e-9)
        XCTAssertNil(ImageLayerFactory.makeLayer(for: Asset(kind: .image, displayName: "x", relativePath: "media/x.jpg"), in: comp),
                     "an image of unknown size cannot be fitted")
        XCTAssertNil(ImageLayerFactory.makeLayer(for: Asset(kind: .video, displayName: "x", relativePath: "media/x.mov", pixelSize: Vec2(x: 1, y: 1)), in: comp))
    }

    func testAddMediaLayerIsOneUndoStepAndKeepsAssetsConsistent() throws {
        let project = makeProject()
        let comp = project.rootComposition
        let asset = Asset(kind: .image, displayName: "a.png", relativePath: "media/a.png", pixelSize: Vec2(x: 100, y: 100))
        let layer = try XCTUnwrap(ImageLayerFactory.makeLayer(for: asset, in: comp))
        let doc = Document(project: project)
        try doc.perform(AddMediaLayer(compositionID: project.rootCompositionID, asset: asset, layer: layer))
        XCTAssertEqual(doc.project.assets, [asset])
        XCTAssertEqual(doc.project.rootComposition.layers.map { $0.id }, [layer.id])
        XCTAssertEqual(doc.undoName, "Import Image")
        doc.undo()
        XCTAssertTrue(doc.project.assets.isEmpty)
        XCTAssertTrue(doc.project.rootComposition.layers.isEmpty)
        doc.redo()
        XCTAssertEqual(doc.project.assets.count, 1)
    }

    func testAddMediaLayerRejectsMismatches() throws {
        let project = makeProject()
        let comp = project.rootComposition
        let asset = Asset(kind: .image, displayName: "a.png", relativePath: "media/a.png", pixelSize: Vec2(x: 100, y: 100))
        let other = Asset(kind: .image, displayName: "b.png", relativePath: "media/b.png", pixelSize: Vec2(x: 100, y: 100))
        let layer = try XCTUnwrap(ImageLayerFactory.makeLayer(for: asset, in: comp))
        let doc = Document(project: project)
        XCTAssertThrowsError(try doc.perform(AddMediaLayer(compositionID: project.rootCompositionID, asset: other, layer: layer))) {
            XCTAssertEqual($0 as? EditError, .invalidAsset)
        }
        let video = Asset(id: asset.id, kind: .video, displayName: "v", relativePath: "media/v.mov")
        XCTAssertThrowsError(try doc.perform(AddMediaLayer(compositionID: project.rootCompositionID, asset: video, layer: layer)))
        XCTAssertTrue(doc.project.assets.isEmpty, "a refused import leaves nothing behind")
    }

    func testImportedMediaSurvivesSavingAndReopening() throws {
        let folder = temporaryProjectFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = try ProjectMedia.importData(Data([5, 6, 7]), fileExtension: "png", baseName: "pic", intoProjectFolder: folder)
        var project = makeProject()
        let asset = Asset(kind: .image, displayName: "pic.png", relativePath: path, pixelSize: Vec2(x: 640, y: 480))
        let layer = try XCTUnwrap(ImageLayerFactory.makeLayer(for: asset, in: project.rootComposition))
        let doc = Document(project: project)
        try doc.perform(AddMediaLayer(compositionID: project.rootCompositionID, asset: asset, layer: layer))
        project = doc.project
        try ProjectFile.save(project, toFolder: folder)

        let reopened = try ProjectFile.load(fromFolder: folder)
        XCTAssertEqual(reopened, project)
        XCTAssertEqual(reopened.assets.first?.pixelSize, Vec2(x: 640, y: 480))
        XCTAssertTrue(ProjectMedia.missingAssets(in: reopened, folder: folder).isEmpty)
        let url = try XCTUnwrap(ProjectMedia.fileURL(for: reopened.assets[0], inProjectFolder: folder))
        XCTAssertEqual(try Data(contentsOf: url), Data([5, 6, 7]))
    }

    func testProjectsSavedBeforePixelSizesExistedStillOpen() throws {
        var project = makeProject()
        project.assets = [Asset(kind: .image, displayName: "old.png", relativePath: "media/old.png", pixelSize: Vec2(x: 10, y: 10))]
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: ProjectFile.encode(project)) as? [String: Any])
        var assets = try XCTUnwrap(object["assets"] as? [[String: Any]])
        assets[0].removeValue(forKey: "pixelSize")
        object["assets"] = assets
        let reopened = try ProjectFile.decode(JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(reopened.assets.count, 1)
        XCTAssertNil(reopened.assets[0].pixelSize)
    }
}
