// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Kenos",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "Kenos",
            path: "Sources/Kenos",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
