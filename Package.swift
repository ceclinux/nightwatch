// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Nightwatch",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "SkyCore", targets: ["SkyCore"]),
        .library(name: "NightwatchUI", targets: ["NightwatchUI"]),
        // The iPhone and iPad app's libraries (Phone/). Its Xcode project is Phone/project.yml.
        .library(name: "PhoneCore", targets: ["PhoneCore"]),
        .library(name: "PhoneUI", targets: ["PhoneUI"]),
        .library(name: "PhoneWidgetUI", targets: ["PhoneWidgetUI"])
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
        .target(name: "PhoneCore", dependencies: ["SkyCore"], path: "Phone/Sources/PhoneCore"),
        .target(name: "PhoneUI", dependencies: ["PhoneCore", "PhoneWidgetUI", "SkyCore"], path: "Phone/Sources/PhoneUI"),
        // What the home-screen widget draws and how the app hands it the snapshot. Kept apart from PhoneUI so the widget stays small.
        .target(name: "PhoneWidgetUI", dependencies: ["SkyCore"], path: "Phone/Sources/PhoneWidgetUI"),
        .testTarget(name: "PhoneCoreTests", dependencies: ["PhoneCore", "PhoneWidgetUI", "SkyCore"], path: "Phone/Tests/PhoneCoreTests"),
        .testTarget(
            name: "SkyCoreTests",
            dependencies: ["SkyCore"],
            path: "Tests/SkyCoreTests",
            resources: [.copy("Fixtures")]
        )
    ]
)
