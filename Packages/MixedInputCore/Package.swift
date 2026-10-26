// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MixedInputCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "MixedInputCore", targets: ["MixedInputCore"])],
    targets: [
        .target(name: "MixedInputCore"),
        .testTarget(name: "MixedInputCoreTests", dependencies: ["MixedInputCore"]),
        .executableTarget(name: "MixedInputBenchmark", dependencies: ["MixedInputCore"]),
    ]
)
