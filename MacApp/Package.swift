// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenChatCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "OpenChatCore", targets: ["OpenChatCore"])
    ],
    targets: [
        .target(
            name: "OpenChatCore",
            path: "OpenChat",
            exclude: [
                "App.swift",
                "ContentView.swift",
                "Info.plist",
                "MarkdownView.swift",
                "OpenChat.entitlements",
                "Resources",
                "SettingsView.swift"
            ],
            sources: [
                "ChatHistory.swift",
                "ChatRequestController.swift",
                "CredentialStore.swift",
                "MediaProcessor.swift",
                "OpenAIClient.swift"
            ]
        ),
        .testTarget(
            name: "OpenChatCoreTests",
            dependencies: ["OpenChatCore"],
            path: "OpenChatTests"
        )
    ]
)
