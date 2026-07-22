// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "fm-steward",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "FMSteward", targets: ["FMSteward"]),
    ],
    targets: [
        .target(
            name: "FMSteward",
            path: "Sources/FMSteward"
        ),
        .testTarget(
            name: "FMStewardTests",
            dependencies: ["FMSteward"],
            path: "Tests/FMStewardTests"
        ),
    ]
)
