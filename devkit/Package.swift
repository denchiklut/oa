// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DevKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DevKit", targets: ["DevKit"]),
        .library(name: "DevKitLive", targets: ["DevKitLive"]),
    ],
    targets: [
        .target(name: "DevKit", resources: [.process("Resources")]),
        .target(name: "DevKitLive", dependencies: ["DevKit"]),
    ]
)
