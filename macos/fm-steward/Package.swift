// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "fm-steward",
    platforms: [
        // Foundation Models (on-device SystemLanguageModel) requires macOS 26+.
        .macOS(.v26),
    ],
    products: [
        .library(name: "FMSteward", targets: ["FMSteward"]),
        .executable(name: "fm-steward", targets: ["fm-steward"]),
    ],
    dependencies: [
        // On-device few-shot retrieval for residual FM (assist only; not security authority).
        // Pin ≥ 0.1.25 — 0.1.24 SPM checkout failed on a broken homebrew-wax submodule.
        // traits: [] disables default MiniLM so text-mode CI stays lean.
        .package(url: "https://github.com/christopherkarani/Wax.git", from: "0.1.25", traits: []),
    ],
    targets: [
        .target(
            name: "FMSteward",
            dependencies: [
                .product(name: "Wax", package: "Wax"),
            ],
            path: "Sources/FMSteward"
        ),
        .executableTarget(
            name: "fm-steward",
            dependencies: ["FMSteward"],
            path: "Sources/fm-steward"
        ),
        .testTarget(
            name: "FMStewardTests",
            dependencies: [
                "FMSteward",
                .product(name: "Wax", package: "Wax"),
            ],
            path: "Tests/FMStewardTests"
        ),
    ]
)
