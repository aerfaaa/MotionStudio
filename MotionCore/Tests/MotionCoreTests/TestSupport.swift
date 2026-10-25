import XCTest
@testable import MotionCore

/// A blank project to test with.
func makeProject(frameRate: FrameRate = .fps30, seconds: Double = 5) -> Project {
    Project.makeNew(name: "Test", width: 1920, height: 1080, frameRate: frameRate, durationSeconds: seconds)
}

/// A simple rectangle layer that lasts for the whole composition.
func makeRect(name: String = "Rect",
              duration: Time,
              position: Vec2 = Vec2(x: 960, y: 540),
              size: Vec2 = Vec2(x: 200, y: 100)) -> Layer {
    Layer(name: name, kind: .shape(.rectangle), size: size, fill: .white,
          inPoint: .zero, outPoint: duration, position: position)
}

func assertEqual(_ a: Vec2, _ b: Vec2, accuracy: Double = 1e-6,
                 file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(a.x, b.x, accuracy: accuracy, file: file, line: line)
    XCTAssertEqual(a.y, b.y, accuracy: accuracy, file: file, line: line)
}
