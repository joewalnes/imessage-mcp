// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "imessage-mcp",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "imessage-mcp",
            path: "Sources/imessage-mcp"
        ),
    ]
)
