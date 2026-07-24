// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "key-kong-prompt",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "KeyKongCore", targets: ["KeyKongCore"]),
        .library(name: "KeyKongMacOS", targets: ["KeyKongMacOS"]),
        .executable(name: "key-kong", targets: ["KeyKongCLI"]),
        .executable(name: "key-kong-prompt", targets: ["KeyKongPromptCLI"])
    ],
    targets: [
        .target(name: "KeyKongCore"),
        .target(name: "KeyKongMacOS", dependencies: ["KeyKongCore"]),
        .executableTarget(
            name: "KeyKongCLI",
            dependencies: ["KeyKongCore", "KeyKongMacOS"]
        ),
        .target(
            name: "KeyKongPrompt",
            dependencies: ["KeyKongCore", "KeyKongMacOS"]
        ),
        .executableTarget(
            name: "KeyKongPromptCLI",
            dependencies: ["KeyKongPrompt"]
        ),
        .testTarget(name: "KeyKongCoreTests", dependencies: ["KeyKongCore"]),
        .testTarget(
            name: "KeyKongMacOSTests",
            dependencies: ["KeyKongCore", "KeyKongMacOS"]
        ),
        .testTarget(
            name: "KeyKongPromptTests",
            dependencies: ["KeyKongPrompt"]
        )
    ]
)
