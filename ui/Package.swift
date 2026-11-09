// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Oa",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Oa", targets: ["Oa"])],
    dependencies: [.package(path: "../devkit")],
    targets: [
        .executableTarget(
            name: "Oa",
            dependencies: [
                .product(name: "DevKit", package: "devkit"),
                .product(name: "DevKitLive", package: "devkit"),
            ]
        )
    ]
)
