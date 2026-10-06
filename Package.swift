// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Aquarium",
    platforms: [.macOS(.v12)],
    dependencies: [
        .package(path: "AquariumCore")
    ],
    targets: [
        .executableTarget(
            name: "aquarium",
            dependencies: [
                .product(name: "AquariumCore", package: "AquariumCore"),
                .product(name: "AquariumAudio", package: "AquariumCore"),
            ],
            path: "Sources/aquarium"
        )
    ]
)
