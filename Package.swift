// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Duply",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "DuplyKit"),
        .executableTarget(name: "duply-launcher", dependencies: ["DuplyKit"]),
        .executableTarget(name: "Duply", dependencies: ["DuplyKit"]),
        .testTarget(name: "DuplyKitTests", dependencies: ["DuplyKit"]),
    ]
)
