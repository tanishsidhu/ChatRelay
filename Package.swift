// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ChatRelay",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ChatRelay", targets: ["ChatRelay"]),
        .executable(name: "chatrelayctl", targets: ["ChatRelayCtl"]),
    ],
    targets: [
        .target(name: "HandoffCore"),
        .executableTarget(
            name: "ChatRelay",
            dependencies: ["HandoffCore"]
        ),
        .executableTarget(
            name: "ChatRelayCtl",
            dependencies: ["HandoffCore"]
        ),
        .testTarget(
            name: "HandoffCoreTests",
            dependencies: ["HandoffCore"]
        ),
    ]
)
