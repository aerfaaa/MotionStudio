import Foundation

/// A 2D transform (move, rotate, scale) stored as a small matrix.
///
/// A point (x, y) becomes (a*x + c*y + tx, b*x + d*y + ty).
/// This is the same layout as CoreGraphics' CGAffineTransform, so the app can
/// hand it straight to the drawing code.
public struct Affine2: Equatable, Codable, Sendable {
    public var a: Double
    public var b: Double
    public var c: Double
    public var d: Double
    public var tx: Double
    public var ty: Double

    public init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
        self.tx = tx
        self.ty = ty
    }

    public static let identity = Affine2(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)

    public static func translation(_ x: Double, _ y: Double) -> Affine2 {
        Affine2(a: 1, b: 0, c: 0, d: 1, tx: x, ty: y)
    }

    public static func scale(_ x: Double, _ y: Double) -> Affine2 {
        Affine2(a: x, b: 0, c: 0, d: y, tx: 0, ty: 0)
    }

    /// Positive degrees turn clockwise on screen (y points down), like After Effects.
    public static func rotation(degrees: Double) -> Affine2 {
        let radians = degrees * Double.pi / 180
        let cosine = cos(radians)
        let sine = sin(radians)
        return Affine2(a: cosine, b: sine, c: -sine, d: cosine, tx: 0, ty: 0)
    }

    public func applying(to point: Vec2) -> Vec2 {
        Vec2(x: a * point.x + c * point.y + tx,
             y: b * point.x + d * point.y + ty)
    }

    /// Combines two transforms: `other` is applied first, then `self`.
    public func concatenating(_ other: Affine2) -> Affine2 {
        Affine2(
            a: a * other.a + c * other.b,
            b: b * other.a + d * other.b,
            c: a * other.c + c * other.d,
            d: b * other.c + d * other.d,
            tx: a * other.tx + c * other.ty + tx,
            ty: b * other.tx + d * other.ty + ty)
    }

    /// The transform that undoes this one, or nil if it squashes space flat (scale of 0).
    public func inverted() -> Affine2? {
        let determinant = a * d - b * c
        guard abs(determinant) > 1e-12 else { return nil }
        let ia = d / determinant
        let ib = -b / determinant
        let ic = -c / determinant
        let id = a / determinant
        let itx = -(ia * tx + ic * ty)
        let ity = -(ib * tx + id * ty)
        return Affine2(a: ia, b: ib, c: ic, d: id, tx: itx, ty: ity)
    }
}
