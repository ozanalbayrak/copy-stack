// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "CopyStack",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CopyStackCore"),
        .executableTarget(
            name: "CopyStack",
            dependencies: ["CopyStackCore"]
        ),
        .testTarget(
            name: "CopyStackCoreTests",
            dependencies: ["CopyStackCore"]
        ),
    ]
)
