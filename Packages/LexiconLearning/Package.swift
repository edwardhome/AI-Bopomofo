// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "LexiconLearning", platforms: [.macOS(.v13)],
    products: [.library(name: "LexiconLearning", targets: ["LearningCore", "LearningStorage", "LearningOrganizer", "LexiconDeployment"])],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "LearningCore"),
        .target(name: "LearningStorage", dependencies: ["LearningCore", "CSQLite"]),
        .target(name: "LearningOrganizer", dependencies: ["LearningCore"]),
        .target(name: "LexiconDeployment", dependencies: ["LearningCore", "LearningStorage"]),
        .testTarget(name: "LearningTests", dependencies: ["LearningCore", "LearningStorage", "LearningOrganizer", "LexiconDeployment"]),
        .executableTarget(name: "LearningBenchmark", dependencies: ["LearningCore"]),
    ])
