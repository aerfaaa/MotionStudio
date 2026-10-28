import UIKit

/// Centralised haptic feedback. The user can disable all app-generated haptics in Settings.
enum MotionStudioHaptics {
    static let preferenceKey = "motionStudioHapticsEnabled"

    static var isEnabled: Bool {
        guard let value = UserDefaults.standard.object(forKey: preferenceKey) as? Bool else { return true }
        return value
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        guard isEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    static func selection() {
        guard isEnabled else { return }
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }

    static func success() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
