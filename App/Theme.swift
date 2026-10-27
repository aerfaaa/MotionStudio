import SwiftUI
import UIKit
import MotionCore

/// Colours, sizes and small helpers shared by every screen.
/// A calm graphite workspace: the composition is the brightest thing on screen,
/// the interface stays quiet, and amber is reserved for keyframes.
enum Theme {
    /// A colour that changes with the Light / Dark appearance.
    private static func adaptive(dark: UIColor, light: UIColor) -> Color {
        Color(uiColor: UIColor { traits in traits.userInterfaceStyle == .dark ? dark : light })
    }

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> UIColor {
        UIColor(red: r, green: g, blue: b, alpha: a)
    }

    static let background = adaptive(dark: rgb(0.063, 0.067, 0.082), light: rgb(0.945, 0.949, 0.965))
    static let surface = adaptive(dark: rgb(0.102, 0.109, 0.133), light: rgb(1.0, 1.0, 1.0))
    static let surfaceRaised = adaptive(dark: rgb(0.148, 0.157, 0.188), light: rgb(0.925, 0.929, 0.949))
    static let hairline = adaptive(dark: UIColor(white: 1, alpha: 0.08), light: UIColor(white: 0, alpha: 0.10))
    static let accent = adaptive(dark: rgb(0.39, 0.55, 1.0), light: rgb(0.20, 0.38, 0.92))
    static let keyframe = adaptive(dark: rgb(1.0, 0.76, 0.28), light: rgb(0.86, 0.55, 0.02))
    static let textPrimary = adaptive(dark: UIColor(white: 1, alpha: 0.95), light: UIColor(white: 0.08, alpha: 0.95))
    static let textSecondary = adaptive(dark: UIColor(white: 1, alpha: 0.58), light: UIColor(white: 0.1, alpha: 0.58))
    static let success = adaptive(dark: rgb(0.36, 0.82, 0.58), light: rgb(0.10, 0.62, 0.36))
    static let danger = adaptive(dark: rgb(1.0, 0.42, 0.40), light: rgb(0.85, 0.18, 0.16))

    static let panelRadius: CGFloat = 18
    static let controlRadius: CGFloat = 11
}

/// The appearance choice in Settings. Saved with @AppStorage under the key "appearance".
enum AppearanceSetting: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "appearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// nil means "follow the system".
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Starting colours for new layers.
enum LayerPalette {
    static let colors: [RGBA] = [
        RGBA(r: 0.39, g: 0.55, b: 1.00),
        RGBA(r: 1.00, g: 0.76, b: 0.28),
        RGBA(r: 0.30, g: 0.82, b: 0.65),
        RGBA(r: 0.98, g: 0.42, b: 0.42),
        RGBA(r: 0.68, g: 0.48, b: 0.98),
        RGBA(r: 0.92, g: 0.92, b: 0.95),
    ]
}

extension RGBA {
    var color: Color {
        Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

extension Vec2 {
    var point: CGPoint { CGPoint(x: x, y: y) }
}

extension Affine2 {
    /// Affine2 uses the same layout as CGAffineTransform.
    var cgAffine: CGAffineTransform {
        CGAffineTransform(a: a, b: b, c: c, d: d, tx: tx, ty: ty)
    }
}

extension View {
    /// A rounded raised surface used for the timeline, inspector and preview areas.
    func panel() -> some View {
        self
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
    }
}


extension MotionCore.RGBA {
    init(color: Color) {
        #if canImport(UIKit)
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 1
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        self.init(r: Double(red), g: Double(green), b: Double(blue), a: Double(alpha))
        #else
        self.init(r: 1, g: 1, b: 1, a: 1)
        #endif
    }
}
