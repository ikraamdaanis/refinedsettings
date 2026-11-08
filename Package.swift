// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Linkguide",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Linkguide", path: "Sources/Linkguide"),
    ]
)
