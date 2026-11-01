// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "LidAwake",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "LidAwakeApp", targets: ["LidAwakeApp"]),
        .executable(name: "lidawake", targets: ["lidawake"]),
        .executable(name: "lidawake-mcp", targets: ["lidawake-mcp"]),
        .library(name: "LidAwakeCore", targets: ["LidAwakeCore"]),
    ],
    targets: [
        .target(name: "LidAwakeCore", linkerSettings: [.linkedFramework("IOKit")]),
        .executableTarget(name: "LidAwakeApp", dependencies: ["LidAwakeCore"]),
        .executableTarget(name: "lidawake", dependencies: ["LidAwakeCore"]),
        .executableTarget(name: "lidawake-mcp", dependencies: ["LidAwakeCore"]),
        .testTarget(name: "LidAwakeCoreTests", dependencies: ["LidAwakeCore"]),
    ]
)
