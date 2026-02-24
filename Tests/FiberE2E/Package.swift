// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FiberE2E",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../.."),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "TestServer",
            dependencies: [
                .product(name: "Hummingbird", package: "hummingbird"),
            ],
            path: "Sources/TestServer"
        ),
        .testTarget(
            name: "E2ETests",
            dependencies: [
                "TestServer",
                .product(name: "Fiber", package: "swift-fiber"),
                .product(name: "FiberTesting", package: "swift-fiber"),
            ],
            path: "Tests/E2ETests"
        ),
    ]
)
