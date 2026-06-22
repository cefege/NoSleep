// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NoSleep",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "NoSleep",
            path: "Sources",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
