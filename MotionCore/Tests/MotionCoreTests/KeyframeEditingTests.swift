import XCTest
@testable import MotionCore

final class KeyframeEditingTests: XCTestCase {

    private let rate = FrameRate.fps30

    private func setUpDocument() throws -> (doc: Document, compID: UUID, layerID: UUID) {
        let project = makeProject()
        let layer = makeRect(duration: project.rootComposition.duration)
        let doc = Document(project: project)
        try doc.perform(AddLayer(compositionID: project.rootCompositionID, layer: layer))
        return (doc, project.rootCompositionID, layer.id)
    }

    private func layer(_ doc: Document, _ id: UUID) -> Layer {
        doc.project.rootComposition.layer(withID: id)!
    }

    private func addOpacityKeyframes(_ doc: Document, _ compID: UUID, _ layerID: UUID, frames: [Int64]) throws {
        for frame in frames {
            try doc.perform(AddKeyframe(compositionID: compID, layerID: layerID, property: .opacity,
                                        time: rate.time(ofFrame: frame)))
        }
    }

    func testMovingAKeyframeKeepsItsValueAndEasing() throws {
        let (doc, compID, id) = try setUpDocument()
        try addOpacityKeyframes(doc, compID, id, frames: [0, 30])
        try doc.perform(SetKeyframeInterpolation(compositionID: compID, layerID: id, property: .opacity,
                                                 time: rate.time(ofFrame: 30), interpolation: .hold))
        try doc.perform(MoveKeyframe(compositionID: compID, layerID: id, property: .opacity,
                                     from: rate.time(ofFrame: 30), to: rate.time(ofFrame: 45)))
        let moved = layer(doc, id).keyframeSnapshots(.opacity)
        XCTAssertEqual(moved.map { $0.time }, [rate.time(ofFrame: 0), rate.time(ofFrame: 45)])
        XCTAssertEqual(moved[1].outgoing, .hold)
        XCTAssertEqual(moved[1].value, .scalar(1.0))
    }

    func testMovingKeyframesCanReorderThem() throws {
        let (doc, compID, id) = try setUpDocument()
        try addOpacityKeyframes(doc, compID, id, frames: [0, 10])
        try doc.perform(MoveKeyframe(compositionID: compID, layerID: id, property: .opacity,
                                     from: rate.time(ofFrame: 0), to: rate.time(ofFrame: 20)))
        XCTAssertEqual(layer(doc, id).keyframeSnapshots(.opacity).map { $0.time },
                       [rate.time(ofFrame: 10), rate.time(ofFrame: 20)])
    }

    func testMovingOntoAnotherKeyframeIsRefusedAndChangesNothing() throws {
        let (doc, compID, id) = try setUpDocument()
        try addOpacityKeyframes(doc, compID, id, frames: [0, 10])
        let before = doc.project
        XCTAssertThrowsError(try doc.perform(MoveKeyframe(compositionID: compID, layerID: id, property: .opacity,
                                                          from: rate.time(ofFrame: 0), to: rate.time(ofFrame: 10)))) {
            XCTAssertEqual($0 as? EditError, .keyframeOccupied)
        }
        XCTAssertEqual(doc.project, before)
    }

    func testMovingAMissingKeyframeIsRefused() throws {
        let (doc, compID, id) = try setUpDocument()
        XCTAssertThrowsError(try doc.perform(MoveKeyframe(compositionID: compID, layerID: id, property: .position,
                                                          from: rate.time(ofFrame: 3), to: rate.time(ofFrame: 4)))) {
            XCTAssertEqual($0 as? EditError, .keyframeNotFound)
        }
    }

    func testDraggingAKeyframeIsOneUndoStep() throws {
        let (doc, compID, id) = try setUpDocument()
        try addOpacityKeyframes(doc, compID, id, frames: [0, 10])
        let beforeDrag = doc.project
        var time = rate.time(ofFrame: 10)
        for frame in [12, 14, 16, 18] as [Int64] {
            let next = rate.time(ofFrame: frame)
            try doc.perform(MoveKeyframe(compositionID: compID, layerID: id, property: .opacity,
                                         from: time, to: next, coalescingKey: "kf-drag"))
            time = next
        }
        doc.undo()
        XCTAssertEqual(doc.project, beforeDrag)
    }

    func testMovingAKeyframeDoesNotChangeTheFixedValue() throws {
        let (doc, compID, id) = try setUpDocument()
        try doc.perform(SetScalarProperty(compositionID: compID, layerID: id, property: .opacity, time: .zero, value: 0.25))
        try doc.perform(AddKeyframe(compositionID: compID, layerID: id, property: .opacity, time: rate.time(ofFrame: 5)))
        let fixedBefore = layer(doc, id).opacity.staticValue
        try doc.perform(MoveKeyframe(compositionID: compID, layerID: id, property: .opacity,
                                     from: rate.time(ofFrame: 5), to: rate.time(ofFrame: 9)))
        XCTAssertEqual(layer(doc, id).opacity.staticValue, fixedBefore)
    }

    func testChangingEasingChangesPlayback() throws {
        let (doc, compID, id) = try setUpDocument()
        try doc.perform(SetScalarProperty(compositionID: compID, layerID: id, property: .opacity, time: .zero, value: 0))
        try addOpacityKeyframes(doc, compID, id, frames: [0])
        try doc.perform(SetScalarProperty(compositionID: compID, layerID: id, property: .opacity,
                                          time: rate.time(ofFrame: 30), value: 100))
        let middle = rate.time(ofFrame: 15)
        XCTAssertEqual(layer(doc, id).opacity.value(at: middle), 50, accuracy: 1e-6)

        try doc.perform(SetKeyframeInterpolation(compositionID: compID, layerID: id, property: .opacity,
                                                 time: rate.time(ofFrame: 0),
                                                 interpolation: EasingPreset.easeIn.interpolation))
        // Ease-in is behind a straight line halfway through (0.3153568 of the way).
        XCTAssertEqual(layer(doc, id).opacity.value(at: middle), 31.53568126, accuracy: 1e-4)

        try doc.perform(SetKeyframeInterpolation(compositionID: compID, layerID: id, property: .opacity,
                                                 time: rate.time(ofFrame: 0), interpolation: .hold))
        XCTAssertEqual(layer(doc, id).opacity.value(at: middle), 0, accuracy: 1e-9)
    }

    func testCopyAndPasteAKeyframeToAnotherTime() throws {
        let (doc, compID, id) = try setUpDocument()
        try doc.perform(SetVectorProperty(compositionID: compID, layerID: id, property: .position,
                                          time: .zero, value: Vec2(x: 10, y: 20)))
        try doc.perform(AddKeyframe(compositionID: compID, layerID: id, property: .position, time: rate.time(ofFrame: 4)))
        var copied = try XCTUnwrap(layer(doc, id).keyframeSnapshot(.position, at: rate.time(ofFrame: 4)))
        copied.time = rate.time(ofFrame: 40)
        try doc.perform(InsertKeyframe(compositionID: compID, layerID: id, property: .position, snapshot: copied))
        let snapshots = layer(doc, id).keyframeSnapshots(.position)
        XCTAssertEqual(snapshots.map { $0.time }, [rate.time(ofFrame: 4), rate.time(ofFrame: 40)])
        XCTAssertEqual(snapshots[1].value, .vector(Vec2(x: 10, y: 20)))
        XCTAssertEqual(doc.undoName, "Paste Keyframe")
    }

    func testPastingTheWrongKindOfValueIsRefused() throws {
        let (doc, compID, id) = try setUpDocument()
        let scalar = KeyframeSnapshot(time: .zero, value: .scalar(1), outgoing: .linear)
        XCTAssertThrowsError(try doc.perform(InsertKeyframe(compositionID: compID, layerID: id,
                                                            property: .position, snapshot: scalar))) {
            XCTAssertEqual($0 as? EditError, .invalidProperty)
        }
    }

    func testDeletingAKeyframeAndUndo() throws {
        let (doc, compID, id) = try setUpDocument()
        try addOpacityKeyframes(doc, compID, id, frames: [0, 10])
        try doc.perform(RemoveKeyframe(compositionID: compID, layerID: id, property: .opacity, time: rate.time(ofFrame: 10)))
        XCTAssertEqual(layer(doc, id).keyframeSnapshots(.opacity).count, 1)
        doc.undo()
        XCTAssertEqual(layer(doc, id).keyframeSnapshots(.opacity).count, 2)
    }

    func testKeyframeEditsSurviveSaveAndReload() throws {
        let (doc, compID, id) = try setUpDocument()
        try addOpacityKeyframes(doc, compID, id, frames: [0, 10])
        try doc.perform(SetKeyframeInterpolation(compositionID: compID, layerID: id, property: .opacity,
                                                 time: rate.time(ofFrame: 0),
                                                 interpolation: EasingPreset.overshoot.interpolation))
        try doc.perform(MoveKeyframe(compositionID: compID, layerID: id, property: .opacity,
                                     from: rate.time(ofFrame: 10), to: rate.time(ofFrame: 25)))
        let reloaded = try ProjectFile.decode(ProjectFile.encode(doc.project))
        XCTAssertEqual(reloaded, doc.project)
        XCTAssertEqual(reloaded.rootComposition.layer(withID: id)?.keyframeSnapshots(.opacity).first?.outgoing,
                       EasingPreset.overshoot.interpolation)
    }

    func testEveryEasingPresetIsAnOrdinaryInterpolation() {
        for preset in EasingPreset.allCases {
            XCTAssertEqual(EasingPreset.matching(preset.interpolation), preset, preset.displayName)
        }
        XCTAssertNil(EasingPreset.matching(.bezier(BezierEase(0.1, 0.2, 0.3, 0.4))))
    }
}
