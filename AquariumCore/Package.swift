// swift-tools-version:5.9
import PackageDescription

/// 어항 시뮬레이션 코어 — 터미널 앱과 데스크톱 앱이 공유한다.
/// Foundation만 쓴다. 터미널 I/O·AppKit·오디오는 여기 들어오지 않는다.
let package = Package(
    name: "AquariumCore",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "AquariumCore", targets: ["AquariumCore"]),
        .library(name: "AquariumAudio", targets: ["AquariumAudio"]),
    ],
    targets: [
        .target(name: "AquariumCore"),
        // 칩튠 BGM — AVFoundation을 쓰므로 Core와 나눈다.
        .target(name: "AquariumAudio", dependencies: ["AquariumCore"]),
        .testTarget(name: "AquariumCoreTests", dependencies: ["AquariumCore"])
    ]
)
