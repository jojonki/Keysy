// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Keysy",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Keysy", path: "Sources/Keysy")
    ]
)
