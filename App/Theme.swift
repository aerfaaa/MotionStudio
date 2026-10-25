import SwiftUI
import MotionCore

/// Colours, sizes and small helpers shared by every screen.
/// A calm graphite workspace: the composition is the brightest thing on screen,
/// the interface stays quiet, and amber is reserved for keyframes.
enum Theme {
    static let background = Color(red: 0.063, green: 0.067, blue: 0.082)
    static let surface = Color(red: 0.102, green: 0.109, blue: 0.133)
    static let surfaceRaised = Color(red: 0.148, green: 0.157, blue: 0.188)
    static let hairline = Color.white.opacity(0.08)
    static let accent = Color(red: 0.39, green: 0.55, blue: 1.0)
    static let keyframe = Color(red: 1.0, green: 0.76, blue: 0.28)
    static let textPrimary = Color.white.opacity(0.95)
    static let textSecondary = Color.white.opacity(0.58)
    static let success = Color(red: 0.36, green: 0.82, blue: 0.58)
    static let danger = Color(red: 1.0, green: 0.42, blue: 0.40)

    static let panelRadius: CGFloat = 18
    static let controlRadius: CGFloat = 11
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
