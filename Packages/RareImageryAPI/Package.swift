// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RareImageryAPI",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "RareImageryAPI", targets: ["RareImageryAPI"])
    ],
    targets: [
        .target(
            name: "RareImageryAPI",
            path: "Sources/RareImageryAPI"
        ),
        .testTarget(
            name: "RareImageryAPITests",
            dependencies: ["RareImageryAPI"],
            path: "Tests/RareImageryAPITests"
        )
    ]
)
