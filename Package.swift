// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexNotchMonitor",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "CodexNotchMonitor", targets: ["CodexNotchMonitor"]),
        .executable(name: "CodexMonitorHook", targets: ["CodexMonitorHook"]),
    ],
    targets: [
        .target(name: "CZstdDecoder", path: "Vendor/Zstd", exclude: ["README.md", "LICENSE"], publicHeadersPath: "include"),
        .executableTarget(
            name: "CodexNotchMonitor",
            dependencies: ["CZstdDecoder"],
            path: "Sources/CodexNotchMonitor"
        ),
        .executableTarget(
            name: "CodexMonitorHook",
            path: "Sources/CodexMonitorHook"
        ),
    ],
    swiftLanguageModes: [.v5]
)
