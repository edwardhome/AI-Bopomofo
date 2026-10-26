// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "AssistanceProbe", platforms: [.macOS(.v26)],
    dependencies: [.package(path: "../../../Packages/CandidateRanking")],
    targets: [.executableTarget(name: "Probe", dependencies: ["CandidateRanking"])])
