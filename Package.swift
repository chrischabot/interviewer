// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Interviewer",
    platforms: [
        .macOS(.v15),
        .iOS(.v18)
    ],
    products: [
        .executable(
            name: "Interviewer",
            targets: ["Interviewer"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "Interviewer",
            dependencies: [],
            path: ".",
            exclude: [
                "Package.swift",
                "PLAN.md",
                "CLAUDE.md",
                "AGENT_ORCHESTRATION.md",
                "README.md",
                "LICENSE",
                "Tests",
                "Tests/Info.plist",
                "anthropic-sdk-typescript",
                "anthropic-swift-sdk",
                "build",
                "images",
                "Essays",
                "Scripts",
                "project.yml",
                "Info.plist",
                "Interviewer.entitlements",
                "AGENTS.md",
                "SWIFT_AGENTS.md"
            ],
            sources: [
                "App",
                "Views",
                "Models",
                "Networking",
                "Security",
                "State",
                "Prompts",
                "Agents"
            ]
        ),
        .testTarget(
            name: "InterviewerTests",
            dependencies: ["Interviewer"],
            path: "Tests",
            exclude: ["Info.plist"]
        )
    ]
)
