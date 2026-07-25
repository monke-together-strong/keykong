// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "key-kong-prompt",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "key-kong-prompt", targets: ["KeyKongPromptCLI"])
    ],
    targets: [
        .target(name: "KeyKongPrompt"),
        .executableTarget(
            name: "KeyKongPromptCLI",
            dependencies: ["KeyKongPrompt"]
        ),
        .testTarget(
            name: "KeyKongPromptTests",
            dependencies: ["KeyKongPrompt"]
        )
    ]
)
