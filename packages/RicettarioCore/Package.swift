// swift-tools-version: 5.9
// Logic package for the Ricettario app. Pure Swift (Foundation only):
// it must build and test on Linux with `swift test`.
import PackageDescription

let package = Package(
    name: "RicettarioCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "RicettarioCore", targets: ["RicettarioCore"])
    ],
    targets: [
        .target(name: "RicettarioCore", path: "Sources/RicettarioCore"),
        .testTarget(name: "RicettarioCoreTests", dependencies: ["RicettarioCore"], path: "Tests/RicettarioCoreTests")
    ]
)
