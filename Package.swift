// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Nightwatch",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SkyCore", targets: ["SkyCore"]),
        .library(name: "NightwatchUI", targets: ["NightwatchUI"])
    ],
    dependencies: [
        .package(url: "https://github.com/gavineadie/SatelliteKit.git", exact: "2.1.2")
    ],
    targets: [
        .target(name: "CAstronomyEngine", path: "Sources/CAstronomyEngine"),
        .target(
            name: "SkyCore",
            dependencies: ["CAstronomyEngine", "SatelliteKit"],
            path: "Sources/SkyCore",
            resources: [.copy("Resources")]
        ),
        .target(name: "NightwatchUI", dependencies: ["SkyCore"], path: "Sources/NightwatchUI"),
        // The app itself (Sources/Nightwatch) and its widget are built by Xcode from project.yml: scripts/build-app.sh.
        .testTarget(
            name: "SkyCoreTests",
            dependencies: ["SkyCore"],
            path: "Tests/SkyCoreTests",
            resources: [.copy("Fixtures")]
        )
    ]
)
