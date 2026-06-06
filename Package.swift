// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DoneP",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "DoneP",
            path: "Sources/DoneP"
        )
    ]
)
