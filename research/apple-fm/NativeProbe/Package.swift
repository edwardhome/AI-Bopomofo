// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "NativeProbe",
    platforms: [.macOS(.v26)],
    dependencies: [.package(path: "../../../Packages/CandidateRanking")],
    targets: [.executableTarget(name: "NativeProbe", dependencies: ["CandidateRanking"])]
)
