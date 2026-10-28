// swift-tools-version:5.9
import PackageDescription

// MotionCore: the editor's brain. No screens, no drawing, no Apple-only frameworks,
// so its tests can run on macOS and on Linux.
let package = Package(
    name: "MotionCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "MotionCore", targets: ["MotionCore"]),
    ],
    targets: [
        .target(name: "MotionCore"),
        .testTarget(name: "MotionCoreTests", dependencies: ["MotionCore"]),
    ]
)
