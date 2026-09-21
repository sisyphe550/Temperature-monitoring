// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TemperatureCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TemperatureCore", targets: ["TemperatureCore"]),
    ],
    targets: [
        .target(
            name: "TemperatureCore",
            path: "Sources/TemperatureCore"
        ),
        .testTarget(
            name: "TemperatureCoreTests",
            dependencies: ["TemperatureCore"],
            path: "Tests/TemperatureCoreTests"
        ),
    ]
)
