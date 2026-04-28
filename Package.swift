// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "CashRunwayWorkspace",
    platforms: [
        .macOS(.v15),
    ],
    dependencies: [
        .package(path: "Modules/CashRunwayCorePackage"),
    ],
    targets: [
        .testTarget(
            name: "CashRunwayCoreTests",
            dependencies: [
                .product(name: "CashRunwayCore", package: "CashRunwayCorePackage"),
            ],
            path: "Tests/CashRunwayCoreTests"
        ),
    ]
)

