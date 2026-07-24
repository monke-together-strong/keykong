// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "key-kong",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "KeyKongCore", targets: ["KeyKongCore"]),
        .library(name: "KeyKongMacOS", targets: ["KeyKongMacOS"]),
        .executable(name: "key-kong", targets: ["KeyKongCLI"])
    ],
    targets: [
        .target(name: "KeyKongCore"),
        .target(name: "KeyKongMacOS", dependencies: ["KeyKongCore"]),
        .executableTarget(
            name: "KeyKongCLI",
            dependencies: ["KeyKongCore", "KeyKongMacOS"]
        ),
        .testTarget(name: "KeyKongCoreTests", dependencies: ["KeyKongCore"]),
        .testTarget(
            name: "KeyKongMacOSTests",
            dependencies: ["KeyKongCore", "KeyKongMacOS"]
        )
    ]
)
