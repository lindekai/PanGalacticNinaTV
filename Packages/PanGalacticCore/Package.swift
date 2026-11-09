// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PanGalacticCore",
    platforms: [
        .tvOS("26.0"),
        .macOS("15.0"), // host for `swift test`
    ],
    products: [
        .library(name: "PanGalacticCore", targets: ["PanGalacticCore"]),
    ],
    targets: [
        .target(name: "PanGalacticCore"),
        .testTarget(name: "PanGalacticCoreTests", dependencies: ["PanGalacticCore"]),
    ]
)
