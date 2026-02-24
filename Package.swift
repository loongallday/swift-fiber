// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-fiber",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8),
    ],
    products: [
        .library(name: "Fiber", targets: ["Fiber"]),
        .library(name: "FiberWebSocket", targets: ["FiberWebSocket"]),
        .library(name: "FiberTesting", targets: ["FiberTesting"]),
        .library(name: "FiberDependencies", targets: ["FiberDependencies"]),
        .library(name: "FiberSharing", targets: ["FiberSharing"]),
        .library(name: "FiberDependenciesTesting", targets: ["FiberDependenciesTesting"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.0.0"),
        .package(url: "https://github.com/pointfreeco/swift-sharing", from: "2.0.0"),
    ],
    targets: [
        // Core networking library
        .target(
            name: "Fiber",
            path: "Sources/Fiber"
        ),
        // WebSocket support
        .target(
            name: "FiberWebSocket",
            dependencies: ["Fiber"],
            path: "Sources/FiberWebSocket"
        ),
        // Testing infrastructure
        .target(
            name: "FiberTesting",
            dependencies: ["Fiber", "FiberWebSocket"],
            path: "Sources/FiberTesting"
        ),
        // swift-dependencies integration
        .target(
            name: "FiberDependencies",
            dependencies: [
                "Fiber",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesMacros", package: "swift-dependencies"),
            ],
            path: "Sources/FiberDependencies"
        ),
        // swift-sharing integration
        .target(
            name: "FiberSharing",
            dependencies: [
                "Fiber",
                .product(name: "Sharing", package: "swift-sharing"),
            ],
            path: "Sources/FiberSharing"
        ),
        // Testing helpers for FiberDependencies
        .target(
            name: "FiberDependenciesTesting",
            dependencies: ["Fiber", "FiberDependencies", "FiberTesting"],
            path: "Sources/FiberDependenciesTesting"
        ),
        // Tests
        .testTarget(
            name: "FiberTests",
            dependencies: ["Fiber", "FiberWebSocket", "FiberTesting"],
            path: "Tests/FiberTests"
        ),
        // Integration tests for new targets
        .testTarget(
            name: "FiberIntegrationTests",
            dependencies: [
                "Fiber", "FiberTesting", "FiberDependencies", "FiberSharing",
                "FiberDependenciesTesting",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "Sharing", package: "swift-sharing"),
            ],
            path: "Tests/FiberIntegrationTests"
        ),
    ]
)
