// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Cadence",
    defaultLocalization: "ru",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Cadence", targets: ["Cadence"]),
        .library(name: "CadenceCore", targets: ["CadenceCore"])
    ],
    targets: [
        .target(
            name: "CadenceCore",
            path: "Sources/CadenceCore"
        ),
        .executableTarget(
            name: "Cadence",
            dependencies: ["CadenceCore"],
            path: "Sources/Cadence"
        ),
        .testTarget(
            name: "CadenceCoreTests",
            dependencies: ["CadenceCore"],
            path: "Tests/CadenceCoreTests"
        ),
    ]
)
