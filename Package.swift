// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Duplex",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "DuplexKit"),
        .executableTarget(name: "duplex-launcher", dependencies: ["DuplexKit"]),
        .executableTarget(name: "Duplex", dependencies: ["DuplexKit"]),
        .testTarget(name: "DuplexKitTests", dependencies: ["DuplexKit"]),
    ]
)
