// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Aquarium",
    targets: [
        .executableTarget(name: "aquarium", path: "Sources/aquarium")
    ]
)
