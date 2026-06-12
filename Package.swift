// swift-tools-version: 6.2
import PackageDescription

let warningFlags: [SwiftSetting] = [
    .unsafeFlags(["-warnings-as-errors"])
]

let package = Package(
    name: "AppleDocsExplorer",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "DocsCore", targets: ["DocsCore"]),
        .executable(name: "DocsCLI", targets: ["DocsCLI"]),
        .executable(name: "DocsMCP", targets: ["DocsMCP"])
    ],
    targets: [
        .target(
            name: "DocsCore",
            path: "Packages/DocsCore/Sources/DocsCore",
            swiftSettings: warningFlags,
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "DocsCLI",
            dependencies: ["DocsCore"],
            path: "Packages/DocsCLI/Sources/DocsCLI",
            swiftSettings: warningFlags
        ),
        .executableTarget(
            name: "DocsMCP",
            dependencies: ["DocsCore"],
            path: "Packages/DocsMCP/Sources/DocsMCP",
            swiftSettings: warningFlags
        ),
        .testTarget(
            name: "DocsCoreTests",
            dependencies: ["DocsCore"],
            path: "Packages/DocsCore/Tests/DocsCoreTests",
            swiftSettings: warningFlags
        )
    ]
)
