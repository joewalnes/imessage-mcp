// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "imessage-mcp",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "IMMessageMCPLib",
            path: "Sources/IMMessageMCPLib"
        ),
        .executableTarget(
            name: "imessage-mcp",
            dependencies: ["IMMessageMCPLib"],
            path: "Sources/imessage-mcp"
        ),
        .testTarget(
            name: "imessage-mcp-tests",
            dependencies: ["IMMessageMCPLib"],
            path: "Tests/imessage-mcp-tests"
        ),
    ]
)
