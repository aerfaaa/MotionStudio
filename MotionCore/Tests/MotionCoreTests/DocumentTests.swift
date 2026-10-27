import XCTest
@testable import MotionCore

final class DocumentTests: XCTestCase {

    private func makeDocument() -> (document: Document, compID: UUID, layer: Layer) {
        let project = makeProject()
        let layer = makeRect(duration: project.rootComposition.duration)
        let document = Document(project: project)
        return (document, project.rootCompositionID, layer)
    }

    private func move(_ compID: UUID, _ layerID: UUID, to x: Double, key: String? = nil) -> SetVectorProperty {
        SetVectorProperty(compositionID: compID, layerID: layerID, property: .position,
                          time: .zero, value: Vec2(x: x, y: 100), coalescingKey: key)
    }

    func testUndoAndRedoRoundTrip() throws {
        let (doc, compID, layer) = makeDocument()
        let original = doc.project
        try doc.perform(AddLayer(compositionID: compID, layer: layer))
        let afterAdd = doc.project
        XCTAssertEqual(afterAdd.rootComposition.layers.count, 1)

        XCTAssertTrue(doc.undo())
        XCTAssertEqual(doc.project, original)
        XCTAssertTrue(doc.canRedo)

        XCTAssertTrue(doc.redo())
        XCTAssertEqual(doc.project, afterAdd)
        XCTAssertFalse(doc.canRedo)
    }

    func testUndoOnEmptyHistoryDoesNothing() {
        let (doc, _, _) = makeDocument()
        XCTAssertFalse(doc.undo())
        XCTAssertFalse(doc.redo())
        XCTAssertFalse(doc.canUndo)
    }

    func testNewEditClearsRedoHistory() throws {
        let (doc, compID, layer) = makeDocument()
        try doc.perform(AddLayer(compositionID: compID, layer: layer))
        doc.undo()
        XCTAssertTrue(doc.canRedo)
        try doc.perform(AddLayer(compositionID: compID, layer: makeRect(name: "Other", duration: layer.outPoint)))
        XCTAssertFalse(doc.canRedo)
    }

    func testUndoAndRedoNames() throws {
        let (doc, compID, layer) = makeDocument()
        try doc.perform(AddLayer(compositionID: compID, layer: layer))
        XCTAssertEqual(doc.undoName, "Add Layer")
        doc.undo()
        XCTAssertNil(doc.undoName)
        XCTAssertEqual(doc.redoName, "Add Layer")
    }

    func testDragEditsWithSameKeyBecomeOneUndoStep() throws {
        let (doc, compID, layer) = makeDocument()
        try doc.perform(AddLayer(compositionID: compID, layer: layer))
        let beforeDrag = doc.project

        try doc.perform(move(compID, layer.id, to: 100, key: "drag"))
        try doc.perform(move(compID, layer.id, to: 200, key: "drag"))
        try doc.perform(move(compID, layer.id, to: 300, key: "drag"))
        assertEqual(doc.project.rootComposition.layers[0].position.staticValue, Vec2(x: 300, y: 100))

        doc.undo()
        XCTAssertEqual(doc.project, beforeDrag, "one undo reverses the whole drag")
        XCTAssertEqual(doc.undoName, "Add Layer")
    }

    func testEndGroupStartsANewUndoStep() throws {
        let (doc, compID, layer) = makeDocument()
        try doc.perform(AddLayer(compositionID: compID, layer: layer))
        try doc.perform(move(compID, layer.id, to: 100, key: "drag"))
        doc.endGroup()
        try doc.perform(move(compID, layer.id, to: 200, key: "drag"))

        doc.undo()
        assertEqual(doc.project.rootComposition.layers[0].position.staticValue, Vec2(x: 100, y: 100))
        doc.undo()
        XCTAssertNotEqual(doc.project.rootComposition.layers[0].position.staticValue, Vec2(x: 100, y: 100))
    }

    func testFailedCommandChangesNothing() throws {
        let (doc, compID, layer) = makeDocument()
        try doc.perform(AddLayer(compositionID: compID, layer: layer))
        let before = doc.project
        let revision = doc.revision

        XCTAssertThrowsError(try doc.perform(RemoveLayer(compositionID: compID, layerID: UUID()))) { error in
            XCTAssertEqual(error as? EditError, .layerNotFound)
        }
        XCTAssertEqual(doc.project, before)
        XCTAssertEqual(doc.revision, revision)
        XCTAssertEqual(doc.undoName, "Add Layer")
    }

    func testEditThatChangesNothingIsNotRecorded() throws {
        let (doc, compID, layer) = makeDocument()
        try doc.perform(AddLayer(compositionID: compID, layer: layer))
        let revision = doc.revision
        // The layer already sits at (960, 540).
        try doc.perform(SetVectorProperty(compositionID: compID, layerID: layer.id, property: .position,
                                          time: .zero, value: Vec2(x: 960, y: 540)))
        XCTAssertEqual(doc.revision, revision)
        XCTAssertEqual(doc.undoName, "Add Layer")
    }

    func testUndoHistoryIsLimited() throws {
        let project = makeProject()
        let layer = makeRect(duration: project.rootComposition.duration)
        let doc = Document(project: project, maxUndoSteps: 3)
        let compID = project.rootCompositionID
        try doc.perform(AddLayer(compositionID: compID, layer: layer))
        for i in 1...5 {
            try doc.perform(RenameLayer(compositionID: compID, layerID: layer.id, newName: "Name \(i)"))
        }
        XCTAssertTrue(doc.undo())
        XCTAssertTrue(doc.undo())
        XCTAssertTrue(doc.undo())
        XCTAssertFalse(doc.undo())
    }

    func testRevisionIncreasesOnEveryChange() throws {
        let (doc, compID, layer) = makeDocument()
        XCTAssertEqual(doc.revision, 0)
        try doc.perform(AddLayer(compositionID: compID, layer: layer))
        XCTAssertEqual(doc.revision, 1)
        doc.undo()
        XCTAssertEqual(doc.revision, 2)
        doc.redo()
        XCTAssertEqual(doc.revision, 3)
    }
}
