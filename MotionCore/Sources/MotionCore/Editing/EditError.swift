import Foundation

/// Why an edit could not be applied. A failed edit never changes the project.
public enum EditError: Error, Equatable {
    case compositionNotFound
    case layerNotFound
    case indexOutOfRange
    case duplicateLayerID
    case invalidProperty
    case invalidTiming
    case keyframeNotFound
    case keyframeOccupied
    case invalidValue
    case effectNotFound
    case effectUnavailable
    case parameterNotFound
    case unsupportedLayerType
    case invalidAsset
}
