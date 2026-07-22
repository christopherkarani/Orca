// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "fm-steward",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "FMSteward", targets: ["FMSteward"]),
        .executable(name: "fm-steward", targets: ["fm-steward"]),
    ],
    targets: [
        .target(
            name: "FMSteward",
            path: "Sources/FMSteward"
        ),
        .executableTarget(
            name: "fm-steward",
            dependencies: ["FMSteward"],
            path: "Sources/fm-steward"
        ),
        .testTarget(
            name: "FMStewardTests",
            dependencies: ["FMSteward"],
            path: "Tests/FMStewardTests"
        ),
    ]
)
