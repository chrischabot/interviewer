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
    targets: [
        .executableTarget(
            name: "Interviewer",
            path: ".",
            exclude: ["Package.swift", "PLAN.md", "CLAUDE.md"],
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
        )
    ]
)
