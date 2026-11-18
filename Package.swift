// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "B8XOC",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "B8XOC", targets: ["B8XOC"])
    ],
    targets: [
        .target(
            name: "B8XOC",
            path: "Sources/Bluetooth",
            sources: ["B8XProtocol.swift"]
        ),
        .testTarget(
            name: "B8XOCTests",
            dependencies: ["B8XOC"],
            path: "Tests"
        )
    ]
)
