// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PhotonMediaKit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v15),
        .macOS(.v11),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "PhotonMediaKit",
            targets: ["PhotonMediaKit", "PhotonMediaKitUI"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(url: "https://github.com/JuniperPhoton/PhotonUtilityKit", branch: "main"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "PhotonMediaKit",
            dependencies: [
                "PhotonUtilityKit"
            ],
            resources: [
                .process("Resources"),
            ]
        ),
        .target(
            name: "PhotonMediaKitUI",
            dependencies: [
                "PhotonMediaKit",
                "PhotonUtilityKit"
            ]
        ),
        .testTarget(
            name: "PhotonMediaKitTests",
            dependencies: ["PhotonMediaKit"]),
    ]
)
