import Foundation

/// Ready-made projects used by tests, screenshots and the demo launch option.
public enum SampleProjects {

    /// A 5-second 1920 x 1080 composition at 29.97 fps with three layers and a few keyframes.
    public static func demo() -> Project {
        var project = Project.makeNew(name: "Demo", width: 1920, height: 1080,
                                      frameRate: .fps29_97, durationSeconds: 5)
        let rate = FrameRate.fps29_97
        let duration = project.rootComposition.duration
        let center = project.rootComposition.center
        let compID = project.rootCompositionID

        // Bottom: a wide card.
        let card = Layer(name: "Card", kind: .shape(.rectangle),
                         size: Vec2(x: 900, y: 420), fill: RGBA(r: 0.20, g: 0.25, b: 0.45),
                         inPoint: .zero, outPoint: duration, position: center)

        // Middle: a circle that slides across and fades in.
        var circle = Layer(name: "Circle", kind: .shape(.ellipse),
                           size: Vec2(x: 360, y: 360), fill: RGBA(r: 0.40, g: 0.55, b: 1.0),
                           inPoint: .zero, outPoint: duration, position: Vec2(x: 560, y: 540))
        let lastFrame = rate.frameCount(for: duration) - 1
        circle.position.setKeyframe(at: rate.time(ofFrame: 0), value: Vec2(x: 560, y: 540),
                                    interpolation: .bezier(.easeInOut))
        circle.position.setKeyframe(at: rate.time(ofFrame: lastFrame), value: Vec2(x: 1360, y: 540))
        circle.opacity.setKeyframe(at: rate.time(ofFrame: 0), value: 0.0)
        circle.opacity.setKeyframe(at: rate.time(ofFrame: 30), value: 1.0)

        // Top: a small amber square that rotates.
        var square = Layer(name: "Square", kind: .shape(.rectangle),
                           size: Vec2(x: 220, y: 220), fill: RGBA(r: 1.0, g: 0.74, b: 0.25),
                           inPoint: rate.time(ofFrame: 15), outPoint: duration,
                           position: Vec2(x: 960, y: 300))
        square.rotation.setKeyframe(at: rate.time(ofFrame: 15), value: 0.0)
        square.rotation.setKeyframe(at: rate.time(ofFrame: lastFrame), value: 180.0)

        try? project.updateComposition(compID) { composition in
            composition.layers = [square, circle, card]   // index 0 = top
        }
        return project
    }
}
