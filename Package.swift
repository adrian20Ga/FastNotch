// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FastNotch",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "FastNotch", targets: ["FastNotch"])
    ],
    targets: [
        .executableTarget(
            name: "FastNotch",
            path: "Sources/FastNotch"
        )
    ]
)
