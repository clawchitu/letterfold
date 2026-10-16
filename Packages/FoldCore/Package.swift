// swift-tools-version: 6.0
import PackageDescription

// FoldCore: the rules of Letterfold, with no UI. A 1:1 port of fold-proto's logic.js and tools/check.js.
let package = Package(
    name: "FoldCore",
    platforms: [.iOS("27.0"), .macOS("15.0")],
    products: [.library(name: "FoldCore", targets: ["FoldCore"])],
    targets: [
        .target(name: "FoldCore", resources: [.copy("Resources/levels.json")]),
        .testTarget(name: "FoldCoreTests", dependencies: ["FoldCore"]),
    ]
)
