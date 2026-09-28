// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GrantTapDesktop",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DesktopInspectorCore", targets: ["DesktopInspectorCore"]),
        .executable(name: "GrantTapDesktop", targets: ["GrantTapDesktop"]),
    ],
    targets: [
        .target(name: "DesktopInspectorCore", exclude: ["README.md"]),
        .executableTarget(name: "GrantTapDesktop", dependencies: ["DesktopInspectorCore"]),
        .testTarget(name: "DesktopInspectorCoreTests", dependencies: ["DesktopInspectorCore"]),
    ]
)
