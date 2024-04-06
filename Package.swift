// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "classdumpctl",
    platforms: [
        .iOS(.v12),
        .macOS(.v10_13),
        .watchOS(.v4),
        .tvOS(.v12),
        .macCatalyst(.v13),
        .visionOS(.v1),
    ],
    products: [
        .executable(
            name: "classdumpctl",
            targets: ["classdumpctl"]
        )
    ],
    dependencies: [
        // using a local package since we already have the package
        // locally since we need it to build using Theos
        .package(path: "ClassDumpRuntime")
    ],
    targets: [
        .executableTarget(
            name: "classdumpctl",
            dependencies: [
                .product(name: "ClassDumpRuntime", package: "ClassDumpRuntime")
            ]
        ),
    ]
)
