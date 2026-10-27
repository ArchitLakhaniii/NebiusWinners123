// swift-tools-version: 6.0
// Licensed under GPL-3.0. See LICENSE.
import PackageDescription

let package = Package(
    name: "BrowserSkills",
    platforms: [.macOS("15.0")],
    products: [
        .executable(name: "BrowserSkills", targets: ["BrowserSkills"]),
    ],
    targets: [
        .executableTarget(
            name: "BrowserSkills",
            path: "Sources/BrowserSkills",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "BrowserSkillsTests",
            dependencies: ["BrowserSkills"],
            path: "Tests/BrowserSkillsTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
