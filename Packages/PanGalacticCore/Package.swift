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
        .library(name: "PanGalacticServices", targets: ["PanGalacticServices"]),
    ],
    targets: [
        // Pure models, wire decoding, allowlist. No I/O.
        .target(name: "PanGalacticCore"),
        // Networking and persistence built on the core (URLSession, Network.framework, UserDefaults).
        .target(name: "PanGalacticServices", dependencies: ["PanGalacticCore"]),
        .testTarget(
            name: "PanGalacticCoreTests",
            dependencies: ["PanGalacticCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "PanGalacticServicesTests", dependencies: ["PanGalacticServices"]),
    ]
)
