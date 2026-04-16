// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ax-recorder",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "ax-recorder",
            path: "Sources/ax-recorder",
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("ApplicationServices"),
            ]
        )
    ]
)
