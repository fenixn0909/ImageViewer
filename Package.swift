// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ImageViewer",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "ImageViewer",
            dependencies: [],
            path: "Sources",
            exclude: ["Info.plist"]
        )
    ]
)
