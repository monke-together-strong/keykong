// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "keykong-prompt",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "keykong-prompt", targets: ["KeyKongPromptCLI"])
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
