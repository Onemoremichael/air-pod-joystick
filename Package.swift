// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "PodStick",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "PodStickCore", targets: ["PodStickCore"]),
        .executable(name: "PodStick", targets: ["PodStick"])
    ],
    targets: [
        .target(name: "PodStickCore"),
        .executableTarget(
            name: "PodStick",
            dependencies: ["PodStickCore"]
        ),
        .testTarget(
            name: "PodStickCoreTests",
            dependencies: ["PodStickCore"]
        )
    ]
)
