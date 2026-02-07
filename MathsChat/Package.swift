// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MathsChat",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/stasel/WebRTC", from: "126.0.0")
    ],
    targets: [
        .executableTarget(
            name: "MathsChat",
            dependencies: [
                .product(name: "WebRTC", package: "WebRTC")
            ],
            path: "Sources"
        )
    ]
)
