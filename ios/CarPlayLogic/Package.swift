// swift-tools-version: 5.9
import PackageDescription

// Host-side unit tests for the UIKit-free CarPlay logic. The sources are
// symlinks into ios/App/App/CarPlay, so the app and these tests always compile
// the same files. Run: swift test --package-path ios/CarPlayLogic
let package = Package(
    name: "CarPlayLogic",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "CarPlayLogic"),
        .testTarget(name: "CarPlayLogicTests", dependencies: ["CarPlayLogic"]),
    ]
)
