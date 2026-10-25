import XCTest
@testable import MotionCore

final class CommandTests: XCTestCase {

    private func setUpDocument() throws -> (doc: Document, compID: UUID, layer: Layer) {
        let project = makeProject()
        let layer = makeRect(duration: project.rootComposition.duration)
        let doc = Document(project: project)
        try doc.perform(AddLayer(compositionID: project.rootCompositionID, layer: layer))
        return (doc, project.rootCompositionID, layer)
    }

    private func currentLayer(_ doc: Document, _ id: UUID) -> Layer {
        doc.project.rootComposition.layer(withID: id)!
    }

    func testAddLayerInsertsAtTheRequestedIndex() throws {
        let (doc, compID, first) = try setUpDocument()
        let second = makeRect(name: "Second", duration: first.outPoint)
        try doc.perform(AddLayer(compositionID: compID, layer: second, index: 1))
        XCTAssertEqual(doc.project.rootComposition.layers.map { $0.id }, [first.id, second.id])
        try doc.perform(AddLayer(compositionID: compID, layer: makeRect(name: "Third", duration: first.outPoint), index: 0))
        XCTAssertEqual(doc.project.rootComposition.layers.first?.name, "Third")
    }

    func testAddLayerRejectsBadIndexAndDuplicateIDs() throws {
        let (doc, compID, first) = try setUpDocument()
        XCTAssertThrowsError(try doc.perform(AddLayer(compositionID: compID, layer: first))) {
            XCTAssertEqual($0 as? EditError, .duplicateLayerID)
        }
        let other = makeRect(name: "Other", duration: first.outPoint)
        XCTAssertThrowsError(try doc.perform(AddLayer(compositionID: compID, layer: other, index: 5))) {
            XCTAssertEqual($0 as? EditError, .indexOutOfRange)
        }
        XCTAssertThrowsError(try doc.perform(AddLayer(compositionID: UUID(), layer: other))) {
            XCTAssertEqual($0 as? EditError, .compositionNotFound)
        }
    }

    func testRemoveLayerClearsParentReferences() throws {
        let (doc, compID, parent) = try setUpDocument()
        var child = makeRect(name: "Child", duration: parent.outPoint)
        child.parentID = parent.id
        try doc.perform(AddLayer(compositionID: compID, layer: child))
        try doc.perform(RemoveLayer(compositionID: compID, layerID: parent.id))
        XCTAssertEqual(doc.project.rootComposition.layers.count, 1)
        XCTAssertNil(currentLayer(doc, child.id).parentID)
    }

    func testReorderLayer() throws {
        let (doc, compID, a) = try setUpDocument()
        let b = makeRect(name: "B", duration: a.outPoint)
        let c = makeRect(name: "C", duration: a.outPoint)
        try doc.perform(AddLayer(compositionID: compID, layer: b, index: 1))
        try doc.perform(AddLayer(compositionID: compID, layer: c, index: 2))
        try doc.perform(ReorderLayer(compositionID: compID, layerID: c.id, newIndex: 0))
        XCTAssertEqual(doc.project.rootComposition.layers.map { $0.name }, ["C", "Rect", "B"])
        XCTAssertThrowsError(try doc.perform(ReorderLayer(compositionID: compID, layerID: c.id, newIndex: 9)))
    }

    func testRenameAndVisibilityAndFill() throws {
        let (doc, compID, layer) = try setUpDocument()
        try doc.perform(RenameLayer(compositionID: compID, layerID: layer.id, newName: "Hero"))
        try doc.perform(SetLayerVisibility(compositionID: compID, layerID: layer.id, isVisible: false))
        try doc.perform(SetLayerFill(compositionID: compID, layerID: layer.id, fill: RGBA(r: 1, g: 0, b: 0)))
        let changed = currentLayer(doc, layer.id)
        XCTAssertEqual(changed.name, "Hero")
        XCTAssertFalse(changed.isVisible)
        XCTAssertEqual(changed.fill, RGBA(r: 1, g: 0, b: 0))
        XCTAssertEqual(doc.undoName, "Change Colour")
    }

    func testLayerTimingMustBeValid() throws {
        let (doc, compID, layer) = try setUpDocument()
        let rate = FrameRate.fps30
        try doc.perform(SetLayerTiming(compositionID: compID, layerID: layer.id,
                                       inPoint: rate.time(ofFrame: 10), outPoint: rate.time(ofFrame: 40)))
        XCTAssertEqual(currentLayer(doc, layer.id).inPoint, rate.time(ofFrame: 10))
        XCTAssertThrowsError(try doc.perform(SetLayerTiming(compositionID: compID, layerID: layer.id,
                                                            inPoint: rate.time(ofFrame: 40), outPoint: rate.time(ofFrame: 10)))) {
            XCTAssertEqual($0 as? EditError, .invalidTiming)
        }
    }

    func testEditingAFixedPropertyChangesTheFixedValue() throws {
        let (doc, compID, layer) = try setUpDocument()
        try doc.perform(SetVectorProperty(compositionID: compID, layerID: layer.id, property: .position,
                                          time: FrameRate.fps30.time(ofFrame: 12), value: Vec2(x: 5, y: 6)))
        let position = currentLayer(doc, layer.id).position
        XCTAssertFalse(position.isAnimated)
        assertEqual(position.staticValue, Vec2(x: 5, y: 6))
    }

    func testEditingAnAnimatedPropertyCreatesAKeyframe() throws {
        let (doc, compID, layer) = try setUpDocument()
        let rate = FrameRate.fps30
        try doc.perform(AddKeyframe(compositionID: compID, layerID: layer.id, property: .opacity, time: rate.time(ofFrame: 0)))
        try doc.perform(SetScalarProperty(compositionID: compID, layerID: layer.id, property: .opacity,
                                          time: rate.time(ofFrame: 30), value: 0.0))
        let opacity = currentLayer(doc, layer.id).opacity
        XCTAssertEqual(opacity.keyframes.count, 2)
        XCTAssertEqual(opacity.value(at: rate.time(ofFrame: 15)), 0.5, accuracy: 1e-9)
    }

    func testAddKeyframeHoldsTheCurrentValue() throws {
        let (doc, compID, layer) = try setUpDocument()
        let rate = FrameRate.fps30
        try doc.perform(SetScalarProperty(compositionID: compID, layerID: layer.id, property: .opacity,
                                          time: .zero, value: 0.4))
        try doc.perform(AddKeyframe(compositionID: compID, layerID: layer.id, property: .opacity, time: rate.time(ofFrame: 20)))
        let opacity = currentLayer(doc, layer.id).opacity
        XCTAssertEqual(opacity.keyframes.count, 1)
        XCTAssertEqual(opacity.keyframes[0].value, 0.4)
        XCTAssertEqual(opacity.keyframes[0].time, rate.time(ofFrame: 20))
    }

    func testRemovingTheLastKeyframeKeepsItsValueAsFixedValue() throws {
        let (doc, compID, layer) = try setUpDocument()
        let time = FrameRate.fps30.time(ofFrame: 7)
        try doc.perform(AddKeyframe(compositionID: compID, layerID: layer.id, property: .position, time: time))
        XCTAssertTrue(currentLayer(doc, layer.id).hasKeyframe(.position, at: time))
        try doc.perform(RemoveKeyframe(compositionID: compID, layerID: layer.id, property: .position, time: time))
        let position = currentLayer(doc, layer.id).position
        XCTAssertFalse(position.isAnimated)
        assertEqual(position.staticValue, Vec2(x: 960, y: 540))
    }

    func testWrongPropertyKindIsRejected() throws {
        let (doc, compID, layer) = try setUpDocument()
        XCTAssertThrowsError(try doc.perform(SetVectorProperty(compositionID: compID, layerID: layer.id, property: .opacity,
                                                               time: .zero, value: .zero))) {
            XCTAssertEqual($0 as? EditError, .invalidProperty)
        }
        XCTAssertThrowsError(try doc.perform(SetScalarProperty(compositionID: compID, layerID: layer.id, property: .position,
                                                               time: .zero, value: 1))) {
            XCTAssertEqual($0 as? EditError, .invalidProperty)
        }
    }

    func testKeyframeUndoRestoresPreviousState() throws {
        let (doc, compID, layer) = try setUpDocument()
        try doc.perform(AddKeyframe(compositionID: compID, layerID: layer.id, property: .position,
                                    time: FrameRate.fps30.time(ofFrame: 3)))
        XCTAssertTrue(currentLayer(doc, layer.id).isAnimated(.position))
        doc.undo()
        XCTAssertFalse(currentLayer(doc, layer.id).isAnimated(.position))
    }
}
