// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TemperatureCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TemperatureCore", targets: ["TemperatureCore"]),
        .library(name: "SensorRuntime", targets: ["SensorRuntime"]),
        .library(name: "TemperaturePresentation", targets: ["TemperaturePresentation"]),
        .executable(name: "ProtocolWorker", targets: ["ProtocolWorker"]),
        .executable(name: "SensorWorker", targets: ["SensorWorker"]),
        .executable(name: "ProductQualification", targets: ["ProductQualification"]),
    ],
    targets: [
        .systemLibrary(
            name: "CSQLite",
            path: "Sources/CSQLite"
        ),
        .target(
            name: "TemperatureCore",
            dependencies: ["CSQLite"],
            path: "Sources/TemperatureCore",
            resources: [
                .copy("Resources/defaults-v1.json"),
                .copy("Resources/first-profile-v1.json"),
                .copy("Resources/schema-v1.sql"),
            ]
        ),
        .target(
            name: "SensorRuntime",
            dependencies: ["TemperatureCore"],
            path: "Sources/SensorRuntime"
        ),
        .target(
            name: "TemperaturePresentation",
            dependencies: ["TemperatureCore"],
            path: "Sources/TemperaturePresentation"
        ),
        .target(
            name: "SensorBridge",
            path: "Sources/SensorBridge",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation"),
            ]
        ),
        .executableTarget(
            name: "ProtocolWorker",
            dependencies: ["SensorRuntime", "TemperatureCore"],
            path: "Tests/Fixtures/ProtocolWorker"
        ),
        .executableTarget(
            name: "SensorWorker",
            dependencies: ["SensorRuntime", "TemperatureCore", "SensorBridge"],
            path: "Sources/SensorWorker",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation"),
            ]
        ),
        .executableTarget(
            name: "ProductQualification",
            dependencies: ["SensorRuntime", "TemperatureCore", "CSQLite"],
            path: "Sources/ProductQualification"
        ),
        .testTarget(
            name: "TemperatureCoreTests",
            dependencies: ["TemperatureCore", "SensorRuntime", "TemperaturePresentation"],
            path: "Tests/TemperatureCoreTests"
        ),
        .testTarget(
            name: "SensorRuntimeTests",
            dependencies: ["SensorRuntime", "TemperatureCore", "SensorBridge"],
            path: "Tests/SensorRuntimeTests"
        ),
    ]
)
