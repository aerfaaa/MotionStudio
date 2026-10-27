import Foundation

/// Everything that is saved: compositions, layers, keyframes and the list of media files.
public struct Project: Codable, Equatable {
    /// Bump this whenever the saved format changes in a way old apps cannot read.
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var name: String
    public var rootCompositionID: UUID
    public var compositions: [Composition]
    public var assets: [Asset]

    public init(schemaVersion: Int = Project.currentSchemaVersion,
                name: String,
                rootCompositionID: UUID,
                compositions: [Composition],
                assets: [Asset] = []) {
        self.schemaVersion = schemaVersion
        self.name = name
        self.rootCompositionID = rootCompositionID
        self.compositions = compositions
        self.assets = assets
    }

    /// A new project with one empty composition.
    public static func makeNew(name: String,
                               width: Int = 1920,
                               height: Int = 1080,
                               frameRate: FrameRate = .fps30,
                               durationSeconds: Double = 5) -> Project {
        let duration = Composition.wholeFrameDuration(seconds: durationSeconds, frameRate: frameRate)
        let composition = Composition(name: "Main", width: width, height: height,
                                      frameRate: frameRate, duration: duration)
        return Project(name: name, rootCompositionID: composition.id, compositions: [composition])
    }

    /// The composition shown in the editor. Falls back to the first one if the id is stale.
    public var rootComposition: Composition {
        compositions.first(where: { $0.id == rootCompositionID }) ?? compositions[0]
    }

    public func composition(withID id: UUID) -> Composition? {
        compositions.first(where: { $0.id == id })
    }

    /// Changes one composition in place. Throws if it does not exist.
    public mutating func updateComposition(_ id: UUID,
                                           _ change: (inout Composition) throws -> Void) throws {
        guard let index = compositions.firstIndex(where: { $0.id == id }) else {
            throw EditError.compositionNotFound
        }
        try change(&compositions[index])
    }

    /// Changes one layer in place. Throws if the composition or layer does not exist.
    public mutating func updateLayer(_ compositionID: UUID, _ layerID: UUID,
                                     _ change: (inout Layer) throws -> Void) throws {
        try updateComposition(compositionID) { composition in
            guard let index = composition.layers.firstIndex(where: { $0.id == layerID }) else {
                throw EditError.layerNotFound
            }
            try change(&composition.layers[index])
        }
    }
}
