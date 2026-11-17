// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "CardProbe", platforms: [.macOS(.v26)], dependencies: [
    .package(path: "../../../Packages/CandidateRanking"),
    .package(path: "../../../Packages/LexiconLearning")
], targets: [.executableTarget(name: "CardProbe", dependencies: [
    .product(name: "CandidateRanking", package: "CandidateRanking"),
    .product(name: "LexiconLearning", package: "LexiconLearning")
])])
