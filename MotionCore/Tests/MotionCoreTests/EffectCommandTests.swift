import XCTest
@testable import MotionCore

final class EffectCommandTests: XCTestCase {

    private struct Setup {
        let doc: Document
        let compID: UUID
        let imageLayerID: UUID
        let solidLayerID: UUID
    }

    private func setUpDocument() throws -> Setup {
        let project = makeProject()
        let comp = project.rootComposition
        let asset = Asset(kind: .image, displayName: "photo.png", relativePath: "media/photo.png", pixelSize: Vec2(x: 800, y: 600))
        let image = try XCTUnwrap(ImageLayerFactory.makeLayer(for: asset, in: comp))
        let solid = makeRect(name: "Box", duration: comp.duration)
        let doc = Document(project: project)
        try doc.perform(AddLayer(compositionID: project.rootCompositionID, layer: solid))
        try doc.perform(AddMediaLayer(compositionID: project.rootCompositionID, asset: asset, layer: image))
        return Setup(doc: doc, compID: project.rootCompositionID, imageLayerID: image.id, solidLayerID: solid.id)
    }

    private func effects(_ s: Setup) -> [EffectInstance] {
        s.doc.project.rootComposition.layer(withID: s.imageLayerID)?.effects ?? []
    }

    private func add(_ s: Setup, _ effectID: String, index: Int? = nil) throws -> UUID {
        let id = UUID()
        try s.doc.perform(AddEffect(compositionID: s.compID, layerID: s.imageLayerID, effectID: effectID, instanceID: id, index: index))
        return id
    }

    func testAddingEffectsKeepsOrderAndAllowsDuplicates() throws {
        let s = try setUpDocument()
        let blur = try add(s, "gaussian-blur")
        let invert = try add(s, "invert")
        let blur2 = try add(s, "gaussian-blur")
        XCTAssertEqual(effects(s).map { $0.id }, [blur, invert, blur2])
        let first = try add(s, "pixelate", index: 0)
        XCTAssertEqual(effects(s).first?.id, first)
        XCTAssertEqual(effects(s).count, 4)
        XCTAssertEqual(s.doc.undoName, "Add Effect")
    }

    func testNewEffectsStartWithTheDefaultSettings() throws {
        let s = try setUpDocument()
        _ = try add(s, "drop-shadow")
        let shadow = try XCTUnwrap(effects(s).first)
        XCTAssertTrue(shadow.isEnabled)
        guard case .scalar(let opacity)? = shadow.parameters["opacity"] else { return XCTFail("no opacity") }
        XCTAssertEqual(opacity.staticValue, 0.6)
        XCTAssertTrue(EffectRegistry.problems(in: shadow).isEmpty)
    }

    func testOnlyAvailableEffectsOnImageLayersCanBeAdded() throws {
        let s = try setUpDocument()
        XCTAssertThrowsError(try s.doc.perform(AddEffect(compositionID: s.compID, layerID: s.solidLayerID, effectID: "invert"))) {
            XCTAssertEqual($0 as? EditError, .unsupportedLayerType)
        }
        XCTAssertThrowsError(try s.doc.perform(AddEffect(compositionID: s.compID, layerID: s.imageLayerID, effectID: "displacement-map"))) {
            XCTAssertEqual($0 as? EditError, .effectUnavailable)
        }
        XCTAssertThrowsError(try s.doc.perform(AddEffect(compositionID: s.compID, layerID: s.imageLayerID, effectID: "bogus"))) {
            XCTAssertEqual($0 as? EditError, .effectUnavailable)
        }
        XCTAssertThrowsError(try s.doc.perform(AddEffect(compositionID: s.compID, layerID: s.imageLayerID, effectID: "invert", index: 5))) {
            XCTAssertEqual($0 as? EditError, .indexOutOfRange)
        }
        XCTAssertNotNil(EffectRegistry.applicabilityMessage(for: .solid))
        XCTAssertNotNil(EffectRegistry.applicabilityMessage(for: .null))
        XCTAssertNil(EffectRegistry.applicabilityMessage(for: .image(assetID: UUID())))
    }

    func testRemoveMoveAndEnable() throws {
        let s = try setUpDocument()
        let a = try add(s, "gaussian-blur")
        let b = try add(s, "invert")
        let c = try add(s, "sharpen")

        try s.doc.perform(MoveEffect(compositionID: s.compID, layerID: s.imageLayerID, instanceID: c, newIndex: 0))
        XCTAssertEqual(effects(s).map { $0.id }, [c, a, b])
        XCTAssertThrowsError(try s.doc.perform(MoveEffect(compositionID: s.compID, layerID: s.imageLayerID, instanceID: c, newIndex: 3))) {
            XCTAssertEqual($0 as? EditError, .indexOutOfRange)
        }

        try s.doc.perform(SetEffectEnabled(compositionID: s.compID, layerID: s.imageLayerID, instanceID: a, isEnabled: false))
        XCTAssertEqual(effects(s).map { $0.isEnabled }, [true, false, true])
        XCTAssertEqual(s.doc.undoName, "Disable Effect")

        try s.doc.perform(RemoveEffect(compositionID: s.compID, layerID: s.imageLayerID, instanceID: b))
        XCTAssertEqual(effects(s).map { $0.id }, [c, a])
        XCTAssertThrowsError(try s.doc.perform(RemoveEffect(compositionID: s.compID, layerID: s.imageLayerID, instanceID: b))) {
            XCTAssertEqual($0 as? EditError, .effectNotFound)
        }
    }

    func testDisabledEffectsKeepTheirSettingsButAreNotResolved() throws {
        let s = try setUpDocument()
        let id = try add(s, "gaussian-blur")
        try s.doc.perform(SetEffectParameters(compositionID: s.compID, layerID: s.imageLayerID, instanceID: id, values: ["radius": [42]]))
        try s.doc.perform(SetEffectEnabled(compositionID: s.compID, layerID: s.imageLayerID, instanceID: id, isEnabled: false))
        let frame = Evaluator.resolve(s.doc.project.rootComposition, frame: 0)
        XCTAssertTrue(frame.layers.first(where: { $0.id == s.imageLayerID })?.effects.isEmpty ?? false)
        try s.doc.perform(SetEffectEnabled(compositionID: s.compID, layerID: s.imageLayerID, instanceID: id, isEnabled: true))
        let again = Evaluator.resolve(s.doc.project.rootComposition, frame: 0)
        XCTAssertEqual(again.layers.first(where: { $0.id == s.imageLayerID })?.effects.first?.values["radius"], [42])
    }

    func testSettingParametersClampsAndValidates() throws {
        let s = try setUpDocument()
        let id = try add(s, "gaussian-blur")
        func set(_ values: [String: [Double]]) throws {
            try s.doc.perform(SetEffectParameters(compositionID: s.compID, layerID: s.imageLayerID, instanceID: id, values: values))
        }
        try set(["radius": [9999], "quality": [0]])
        guard case .scalar(let radius)? = effects(s)[0].parameters["radius"] else { return XCTFail("no radius") }
        XCTAssertEqual(radius.staticValue, 250)
        guard case .scalar(let quality)? = effects(s)[0].parameters["quality"] else { return XCTFail("no quality") }
        XCTAssertEqual(quality.staticValue, 0)

        XCTAssertThrowsError(try set(["nonsense": [1]])) { XCTAssertEqual($0 as? EditError, .parameterNotFound) }
        XCTAssertThrowsError(try set(["radius": [1, 2]])) { XCTAssertEqual($0 as? EditError, .invalidValue) }
        XCTAssertThrowsError(try set(["radius": [.nan]])) { XCTAssertEqual($0 as? EditError, .invalidValue) }
        XCTAssertThrowsError(try s.doc.perform(SetEffectParameters(compositionID: s.compID, layerID: s.imageLayerID,
                                                                    instanceID: UUID(), values: ["radius": [1]]))) {
            XCTAssertEqual($0 as? EditError, .effectNotFound)
        }
        XCTAssertTrue(EffectRegistry.problems(in: effects(s)[0]).isEmpty)
    }

    func testVectorAndColourSettings() throws {
        let s = try setUpDocument()
        let split = try add(s, "rgb-split")
        try s.doc.perform(SetEffectParameters(compositionID: s.compID, layerID: s.imageLayerID, instanceID: split,
                                              values: ["redOffset": [3, -4]]))
        guard case .vector(let red)? = effects(s)[0].parameters["redOffset"] else { return XCTFail("no offset") }
        XCTAssertEqual(red.staticValue, Vec2(x: 3, y: -4))
        XCTAssertThrowsError(try s.doc.perform(SetEffectParameters(compositionID: s.compID, layerID: s.imageLayerID,
                                                                    instanceID: split, values: ["redOffset": [3]])))

        let shadow = try add(s, "drop-shadow")
        // A colour is three settings that must change together, in a single undo step.
        try s.doc.perform(SetEffectParameters(compositionID: s.compID, layerID: s.imageLayerID, instanceID: shadow,
                                              values: ["shadowRed": [1], "shadowGreen": [0.5], "shadowBlue": [0.25]]))
        let values = EffectValues(values: ["shadowRed": [1], "shadowGreen": [0.5], "shadowBlue": [0.25]],
                                  definition: EffectRegistry.definition(id: "drop-shadow"))
        XCTAssertEqual(values.color("shadow").1, 0.5)
        s.doc.undo()
        guard case .scalar(let green)? = effects(s)[1].parameters["shadowGreen"] else { return XCTFail("no green") }
        XCTAssertEqual(green.staticValue, 0)
    }

    func testDraggingASliderIsOneUndoStep() throws {
    let s = try setUpDocument()
    let id = try add(s, "gaussian-blur")
    let before = s.doc.project

    for radius in [5.0, 10, 15, 20] {
        try s.doc.perform(
            SetEffectParameters(
                compositionID: s.compID,
                layerID: s.imageLayerID,
                instanceID: id,
                values: ["radius": [radius]],
                coalescingKey: "slider"
            )
        )
    }

    XCTAssertTrue(s.doc.undo())

    guard case .scalar(let radius)? = effects(s)[0].parameters["radius"] else {
        return XCTFail("no radius")
    }

    XCTAssertEqual(radius.staticValue, 10, "back to the default it had before the drag")
    XCTAssertEqual(s.doc.project, before, "undo should restore the project before the slider drag")
}
    func testAnAnimatedSettingGetsAKeyframeInsteadOfAFixedValue() throws {
        let s = try setUpDocument()
        let id = try add(s, "brightness-contrast")
        // Give the setting a keyframe, then edit it at another time.
        var project = s.doc.project
        try project.updateLayer(s.compID, s.imageLayerID) { layer in
            var track = AnimatedProperty(0.0)
            track.setKeyframe(at: .zero, value: 0)
            layer.effects[0].parameters["brightness"] = .scalar(track)
        }
        let animated = Document(project: project)
        let later = FrameRate.fps30.time(ofFrame: 30)
        try animated.perform(SetEffectParameters(compositionID: s.compID, layerID: s.imageLayerID, instanceID: id,
                                                 values: ["brightness": [0.8]], time: later))
        guard case .scalar(let track)? = animated.project.rootComposition.layer(withID: s.imageLayerID)?.effects[0].parameters["brightness"] else {
            return XCTFail("no brightness")
        }
        XCTAssertEqual(track.keyframes.count, 2)
        XCTAssertEqual(track.value(at: later), 0.8, accuracy: 1e-9)
    }

    func testResetRestoresDefaultsButKeepsIdentityAndEnabledState() throws {
        let s = try setUpDocument()
        let id = try add(s, "gaussian-blur")
        try s.doc.perform(SetEffectParameters(compositionID: s.compID, layerID: s.imageLayerID, instanceID: id, values: ["radius": [99]]))
        try s.doc.perform(SetEffectEnabled(compositionID: s.compID, layerID: s.imageLayerID, instanceID: id, isEnabled: false))
        try s.doc.perform(ResetEffect(compositionID: s.compID, layerID: s.imageLayerID, instanceID: id))
        let effect = effects(s)[0]
        XCTAssertEqual(effect.id, id)
        XCTAssertFalse(effect.isEnabled)
        guard case .scalar(let radius)? = effect.parameters["radius"] else { return XCTFail("no radius") }
        XCTAssertEqual(radius.staticValue, 10)
    }

    func testEveryEffectEditCanBeUndoneAndRedone() throws {
        let s = try setUpDocument()
        let start = s.doc.project
        let id = try add(s, "vignette")
        try s.doc.perform(SetEffectParameters(compositionID: s.compID, layerID: s.imageLayerID, instanceID: id, values: ["intensity": [0.9]]))
        try s.doc.perform(MoveEffect(compositionID: s.compID, layerID: s.imageLayerID, instanceID: id, newIndex: 0))
        try s.doc.perform(RemoveEffect(compositionID: s.compID, layerID: s.imageLayerID, instanceID: id))
        let end = s.doc.project
        for _ in 0..<4 { s.doc.undo() }
        XCTAssertEqual(s.doc.project.rootComposition.layer(withID: s.imageLayerID)?.effects.count, 0)
        for _ in 0..<4 { s.doc.redo() }
        XCTAssertEqual(s.doc.project, end)
        XCTAssertNotEqual(start, end)
    }

    // MARK: Saving

    func testEffectStacksSurviveSavingWithOrderEnabledStateAndValues() throws {
        let s = try setUpDocument()
        let blur = try add(s, "gaussian-blur")
        let invert = try add(s, "invert")
        let glow = try add(s, "glow")
        try s.doc.perform(SetEffectParameters(compositionID: s.compID, layerID: s.imageLayerID, instanceID: blur, values: ["radius": [33]]))
        try s.doc.perform(SetEffectEnabled(compositionID: s.compID, layerID: s.imageLayerID, instanceID: invert, isEnabled: false))
        try s.doc.perform(SetEffectParameters(compositionID: s.compID, layerID: s.imageLayerID, instanceID: glow,
                                              values: ["colorRed": [0.25], "mode": [1]]))
        let reloaded = try ProjectFile.decode(ProjectFile.encode(s.doc.project))
        XCTAssertEqual(reloaded, s.doc.project)
        let stack = try XCTUnwrap(reloaded.rootComposition.layer(withID: s.imageLayerID)?.effects)
        XCTAssertEqual(stack.map { $0.effectID }, ["gaussian-blur", "invert", "glow"])
        XCTAssertEqual(stack.map { $0.isEnabled }, [true, false, true])
        let resolved = Evaluator.resolve(reloaded.rootComposition, frame: 0).layers.first(where: { $0.id == s.imageLayerID })
        XCTAssertEqual(resolved?.effects.map { $0.effectID }, ["gaussian-blur", "glow"])
        XCTAssertEqual(resolved?.effects.first?.values["radius"], [33])
    }

    func testUnknownEffectsInAFileAreKeptAndSkippedWhenProcessing() throws {
        let s = try setUpDocument()
        var project = s.doc.project
        try project.updateLayer(s.compID, s.imageLayerID) { layer in
            layer.effects = [EffectInstance(effectID: "from-a-newer-version", parameters: ["x": .scalar(AnimatedProperty(1.0))])]
        }
        let reloaded = try ProjectFile.decode(ProjectFile.encode(project))
        XCTAssertEqual(reloaded.rootComposition.layer(withID: s.imageLayerID)?.effects.first?.effectID, "from-a-newer-version")
        let resolved = Evaluator.resolve(reloaded.rootComposition, frame: 0).layers.first(where: { $0.id == s.imageLayerID })
        let result = EffectPipeline.apply(resolved?.effects ?? [], to: PixelImage.filled(width: 2, height: 2, r: 1, g: 1, b: 1), scale: 1)
        XCTAssertEqual(result.issues.count, 1)
        XCTAssertEqual(result.image, PixelImage.filled(width: 2, height: 2, r: 1, g: 1, b: 1))
    }

    func testProjectsWithoutEffectsOrMediaStillOpen() throws {
        let plain = SampleProjects.demo()
        let reloaded = try ProjectFile.decode(ProjectFile.encode(plain))
        XCTAssertEqual(reloaded, plain)
        XCTAssertTrue(reloaded.assets.isEmpty)
        XCTAssertTrue(reloaded.rootComposition.layers.allSatisfy { $0.effects.isEmpty })
    }

    func testAllFifteenEffectsAreAvailableAndPartial() {
        let expected: Set<String> = ["brightness-contrast", "hue-shift", "saturation-vibrance", "invert", "gaussian-blur", "sharpen",
                                     "vignette", "drop-shadow", "glow", "gradient-map", "rgb-split", "pixelate", "posterize",
                                     "directional-blur", "wave-warp"]
        XCTAssertEqual(Set(ImageEffects.availableIDs), expected)
        XCTAssertEqual(Set(EffectRegistry.available.map { $0.id }), expected)
        for id in expected {
            XCTAssertEqual(EffectRegistry.definition(id: id)?.status, .partial, id)
            XCTAssertNotNil(EffectRegistry.makeInstance(id: id), id)
        }
    }
}
