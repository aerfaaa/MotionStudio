import Foundation

/// A frame rate offered when creating a project.
public struct FrameRateOption: Identifiable, Hashable, Sendable {
    public var id: String { label }
    public let label: String
    public let rate: FrameRate

    public init(label: String, rate: FrameRate) {
        self.label = label
        self.rate = rate
    }

    /// Any rate works in the engine. These are the ones the New Project screen offers.
    public static let all: [FrameRateOption] = [
        FrameRateOption(label: "23.976 fps", rate: .fps23_976),
        FrameRateOption(label: "24 fps", rate: .fps24),
        FrameRateOption(label: "25 fps", rate: .fps25),
        FrameRateOption(label: "29.97 fps", rate: .fps29_97),
        FrameRateOption(label: "30 fps", rate: .fps30),
        FrameRateOption(label: "50 fps", rate: .fps50),
        FrameRateOption(label: "59.94 fps", rate: .fps59_94),
        FrameRateOption(label: "60 fps", rate: .fps60),
        FrameRateOption(label: "120 fps", rate: .fps120),
    ]
}

/// A composition size offered when creating a project.
public struct ResolutionPreset: Identifiable, Hashable, Sendable {
    public var id: String { label }
    public let label: String
    public let width: Int
    public let height: Int

    public init(label: String, width: Int, height: Int) {
        self.label = label
        self.width = width
        self.height = height
    }

    public static let all: [ResolutionPreset] = [
        ResolutionPreset(label: "Full HD, 1920 x 1080", width: 1920, height: 1080),
        ResolutionPreset(label: "Vertical, 1080 x 1920", width: 1080, height: 1920),
        ResolutionPreset(label: "Square, 1080 x 1080", width: 1080, height: 1080),
        ResolutionPreset(label: "HD, 1280 x 720", width: 1280, height: 720),
        ResolutionPreset(label: "4K UHD, 3840 x 2160", width: 3840, height: 2160),
    ]
}
