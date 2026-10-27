import Foundation

/// Converts between composition pixels and on-screen points.
///
/// The composition (for example 1920 x 1080) is fitted inside the available view and centred.
/// The composition size lives in the project; the view size is whatever the device gives us.
/// Every tap and every drawing step goes through this one type, so the two never get mixed up.
public struct Viewport: Equatable, Sendable {
    public var compWidth: Double
    public var compHeight: Double
    public var viewWidth: Double
    public var viewHeight: Double
    /// 1 = fitted to the view. 2 = twice as big.
    public var zoom: Double
    /// Extra shift in view points.
    public var pan: Vec2

    public init(compWidth: Double, compHeight: Double,
                viewWidth: Double, viewHeight: Double,
                zoom: Double = 1, pan: Vec2 = .zero) {
        self.compWidth = compWidth
        self.compHeight = compHeight
        self.viewWidth = viewWidth
        self.viewHeight = viewHeight
        self.zoom = zoom
        self.pan = pan
    }

    /// View points per composition pixel.
    public var scale: Double {
        guard compWidth > 0, compHeight > 0, viewWidth > 0, viewHeight > 0 else { return 1 }
        return min(viewWidth / compWidth, viewHeight / compHeight) * zoom
    }

    /// Where the composition's top-left corner sits in the view.
    public var origin: Vec2 {
        let s = scale
        return Vec2(x: (viewWidth - compWidth * s) / 2 + pan.x,
                    y: (viewHeight - compHeight * s) / 2 + pan.y)
    }

    public func compToView(_ point: Vec2) -> Vec2 {
        let o = origin
        let s = scale
        return Vec2(x: point.x * s + o.x, y: point.y * s + o.y)
    }

    public func viewToComp(_ point: Vec2) -> Vec2 {
        let o = origin
        let s = scale
        return Vec2(x: (point.x - o.x) / s, y: (point.y - o.y) / s)
    }

    /// The transform that maps composition pixels to view points.
    public var compToViewTransform: Affine2 {
        let o = origin
        let s = scale
        return Affine2(a: s, b: 0, c: 0, d: s, tx: o.x, ty: o.y)
    }
}
