// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TabPad",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "TabPad", targets: ["TabPad"])],
    targets: [
        .target(
            name: "TrackpadBridge",
            path: "Sources/TrackpadBridge",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "TabPad",
            dependencies: ["TrackpadBridge"],
            path: "Sources/TabPad",
            linkerSettings: [.linkedFramework("SwiftUI"), .linkedFramework("AppKit")]
        )
    ]
)
