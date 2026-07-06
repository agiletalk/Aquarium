// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Aquarium",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(name: "aquarium", path: "Sources/aquarium")
    ]
)
