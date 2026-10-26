// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CandidateRanking",
    platforms: [.macOS(.v13)],
    products: [.library(name: "CandidateRanking", targets: ["CandidateRanking"])],
    targets: [
        .target(name: "CandidateRanking"),
        .testTarget(name: "CandidateRankingTests", dependencies: ["CandidateRanking"]),
    ]
)
