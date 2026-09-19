// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SensorProbe",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "sensor-probe", targets: ["SensorProbe"])],
    targets: [
        .target(name: "SensorBridge", linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]),
        .target(name: "ProbeCore"),
        .executableTarget(name: "SensorProbe", dependencies: ["ProbeCore", "SensorBridge"]),
        .testTarget(name: "ProbeCoreTests", dependencies: ["ProbeCore"])
    ]
)
