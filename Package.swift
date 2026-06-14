// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Shelve",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "Shelve",
            path: "Sources/Shelve",
            resources: [
                .copy("Assets")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
