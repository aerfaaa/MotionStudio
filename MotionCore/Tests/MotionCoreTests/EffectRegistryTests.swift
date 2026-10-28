import XCTest
@testable import MotionCore

final class EffectRegistryTests: XCTestCase {

    func testEveryRequiredEffectNameIsRegisteredExactly() {
        let registered = Set(EffectRegistry.all.map { $0.name })
        let missing = requiredEffectNames.filter { !registered.contains($0) }
        XCTAssertTrue(missing.isEmpty, "Missing from the catalogue: \(missing)")
    }

    func testTheCatalogueHasNoDuplicatesAndOnlyKnownExtras() {
        XCTAssertEqual(requiredEffectNames.count, Set(requiredEffectNames).count, "the required list has duplicates")
        let names = EffectRegistry.all.map { $0.name }
        XCTAssertEqual(names.count, Set(names).count, "the catalogue has duplicate names")
        // These additional mobile-focused effects are intentionally outside the base required list.
        let extras = Set(names).subtracting(requiredEffectNames)
        XCTAssertEqual(extras, ["Drop Shadow", "Luma Fade", "VHS", "Pixel Sort", "RGB Blur", "Motion Tile",
                                "Black & White", "Sepia Tone", "Solarize", "Tint"])
    }

    func testSpecialCharactersInNamesArePreserved() {
        let names = Set(EffectRegistry.all.map { $0.name })
        for name in ["360º Reorient Sphere", "Omino Diffusion+", "Brightness / Contrast", "Count Up/Down",
                     "Channel Remap (HSV)", "Inner Pinch/Bulge", "Four-color Gradient", "RGB Split", "Auto-Shake"] {
            XCTAssertTrue(names.contains(name), name)
        }
    }

    func testIDsAreUniqueAndStable() {
        let ids = EffectRegistry.all.map { $0.id }
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(EffectRegistry.slug("Channel Remap (HSV)"), "channel-remap-hsv")
        XCTAssertEqual(EffectRegistry.slug("360º Reorient Sphere"), "360-reorient-sphere")
        XCTAssertEqual(EffectRegistry.slug("Omino Diffusion+"), "omino-diffusion")
        XCTAssertEqual(EffectRegistry.definition(id: "gaussian-blur")?.name, "Gaussian Blur")
        XCTAssertNil(EffectRegistry.definition(id: "does-not-exist"))
    }

    func testEveryEffectHasACategory() {
        for category in EffectCategory.allCases {
            XCTAssertFalse(EffectRegistry.definitions(in: category).isEmpty, category.displayName)
        }
        let total = EffectCategory.allCases.reduce(0) { $0 + EffectRegistry.definitions(in: $1).count }
        XCTAssertEqual(total, EffectRegistry.all.count)
    }

    func testAnEffectIsNeverLabelledFinishedWithoutProcessingCode() {
        for definition in EffectRegistry.all {
            if ImageEffects.isAvailable(definition.id) {
                XCTAssertEqual(definition.status, .partial, definition.name)
            } else {
                XCTAssertEqual(definition.status, .missing, definition.name)
            }
        }
        // Nothing is "working" until its tests have been run and have passed.
        XCTAssertFalse(EffectRegistry.all.contains(where: { $0.status == .working }))
    }

    func testSearch() {
        XCTAssertTrue(EffectRegistry.search("blur").contains(where: { $0.name == "Gaussian Blur" }))
        XCTAssertTrue(EffectRegistry.search("GLOW").count >= 5)
        XCTAssertEqual(EffectRegistry.search("zzzz").count, 0)
        XCTAssertEqual(EffectRegistry.search("  ").count, EffectRegistry.all.count)
        XCTAssertTrue(EffectRegistry.search("360").count >= 2)
    }

    func testDefaultsAreInsideTheirRanges() {
        for definition in EffectRegistry.all {
            for parameter in definition.parameters {
                switch parameter.kind {
                case .scalar(let minimum, let maximum, let defaultValue):
                    XCTAssertLessThan(minimum, maximum, "\(definition.name) \(parameter.name)")
                    XCTAssertTrue((minimum...maximum).contains(defaultValue), "\(definition.name) \(parameter.name)")
                case .choice(let options, let defaultIndex):
                    XCTAssertTrue(options.indices.contains(defaultIndex), "\(definition.name) \(parameter.name)")
                case .vector:
                    break
                }
            }
            XCTAssertEqual(Set(definition.parameters.map { $0.id }).count, definition.parameters.count, definition.name)
        }
    }

    func testTheEffectsNamedInTheSpecificationHaveTheirParameters() {
        func ids(_ effect: String) -> Set<String> {
            Set(EffectRegistry.definition(id: effect)?.parameters.map { $0.id } ?? [])
        }
        XCTAssertTrue(ids("gaussian-blur").isSuperset(of: ["radius", "quality", "edges"]))
        XCTAssertTrue(ids("glow").isSuperset(of: ["threshold", "radius", "intensity"]))
        XCTAssertTrue(ids("rgb-split").isSuperset(of: ["redOffset", "blueOffset", "intensity"]))
        XCTAssertTrue(ids("displacement-map").isSuperset(of: ["horizontal", "vertical", "edges"]))
        XCTAssertTrue(ids("wave-warp").isSuperset(of: ["amplitude", "frequency", "phase", "direction", "waveType"]))
        XCTAssertTrue(ids("chroma-key").isSuperset(of: ["tolerance", "edgeSoftness", "spillSuppression"]))
        XCTAssertTrue(ids("motion-blur").isSuperset(of: ["shutterAngle", "samples", "quality"]))
    }

    func testMakeInstanceUsesDefaults() throws {
        let blur = try XCTUnwrap(EffectRegistry.makeInstance(id: "gaussian-blur"))
        XCTAssertEqual(blur.effectID, "gaussian-blur")
        XCTAssertTrue(blur.isEnabled)
        guard case .scalar(let radius)? = blur.parameters["radius"] else { return XCTFail("no radius") }
        XCTAssertEqual(radius.staticValue, 10)
        guard case .scalar(let quality)? = blur.parameters["quality"] else { return XCTFail("no quality") }
        XCTAssertEqual(quality.staticValue, 1)
        guard case .vector(let offset)? = EffectRegistry.makeInstance(id: "rgb-split")?.parameters["redOffset"] else {
            return XCTFail("no red offset")
        }
        XCTAssertEqual(offset.staticValue, Vec2(x: -8, y: 0))
        XCTAssertNil(EffectRegistry.makeInstance(id: "nope"))
        XCTAssertTrue(EffectRegistry.problems(in: blur).isEmpty)
    }

    func testValidationFindsAndRepairsBadSettings() throws {
        var blur = try XCTUnwrap(EffectRegistry.makeInstance(id: "gaussian-blur"))
        blur.parameters["radius"] = .scalar(AnimatedProperty(9999.0, keyframes: [
            Keyframe(time: .zero, value: -5.0), Keyframe(time: Time(seconds: 1), value: 40.0),
        ]))
        blur.parameters["quality"] = .scalar(AnimatedProperty(7.0))
        blur.parameters["bogus"] = .scalar(AnimatedProperty(1.0))
        blur.parameters["edges"] = .vector(AnimatedProperty(Vec2.zero))
        XCTAssertEqual(EffectRegistry.problems(in: blur).count, 4)

        let repaired = EffectRegistry.repaired(blur)
        XCTAssertTrue(EffectRegistry.problems(in: repaired).isEmpty)
        guard case .scalar(let radius)? = repaired.parameters["radius"] else { return XCTFail("no radius") }
        XCTAssertEqual(radius.staticValue, 250)
        XCTAssertEqual(radius.keyframes.map { $0.value }, [0, 40])
        guard case .scalar(let quality)? = repaired.parameters["quality"] else { return XCTFail("no quality") }
        XCTAssertEqual(quality.staticValue, 2)
        XCTAssertNil(repaired.parameters["bogus"])

        XCTAssertEqual(EffectRegistry.problems(in: EffectInstance(effectID: "nope")).count, 1)
    }

    func testClampHelper() {
        XCTAssertEqual(EffectRegistry.clamp(5, for: .scalar(min: 0, max: 1, defaultValue: 0)), 1)
        XCTAssertEqual(EffectRegistry.clamp(-5, for: .scalar(min: 0, max: 1, defaultValue: 0)), 0)
        XCTAssertEqual(EffectRegistry.clamp(1.6, for: .choice(options: ["a", "b", "c"], defaultIndex: 0)), 2)
        XCTAssertEqual(EffectRegistry.clamp(9, for: .choice(options: ["a", "b"], defaultIndex: 0)), 1)
    }

    func testEffectStacksSurviveSavingAndKeepTheirOrder() throws {
        var project = SampleProjects.demo()
        let compID = project.rootCompositionID
        let layerID = project.rootComposition.layers[0].id
        var blur = try XCTUnwrap(EffectRegistry.makeInstance(id: "gaussian-blur"))
        blur.isEnabled = false
        let glow = try XCTUnwrap(EffectRegistry.makeInstance(id: "glow"))
        try project.updateLayer(compID, layerID) { $0.effects = [glow, blur] }
        let reloaded = try ProjectFile.decode(ProjectFile.encode(project))
        let stack = try XCTUnwrap(reloaded.rootComposition.layer(withID: layerID)?.effects)
        XCTAssertEqual(stack.map { $0.effectID }, ["glow", "gaussian-blur"])
        XCTAssertEqual(stack.map { $0.isEnabled }, [true, false])
        // A disabled effect keeps its settings but is skipped by the evaluator.
        let resolved = Evaluator.resolve(reloaded.rootComposition, frame: 15).layers.first(where: { $0.id == layerID })
        XCTAssertEqual(resolved?.effects.map { $0.effectID }, ["glow"])
    }
    func testVHSHasRealtimeTuningControls() {
        let definition = try! XCTUnwrap(EffectRegistry.definition(id: "vhs"))
        XCTAssertEqual(definition.parameters.map(\.id),
                       ["intensity", "tracking", "scanlines", "chromaLoss", "noise", "tapeMode"])
        XCTAssertEqual(definition.parameters.last?.name, "Tape speed")
        XCTAssertEqual(EffectRegistry.makeInstance(id: "vhs")?.parameters["tapeMode"],
                       .scalar(AnimatedProperty(0)))
    }

}
