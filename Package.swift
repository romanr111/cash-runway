// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SpendeeLedgerWorkspace",
    platforms: [
        .macOS(.v15),
    ],
    dependencies: [
        .package(path: "Modules/LedgerCorePackage"),
    ],
    targets: [
        .testTarget(
            name: "LedgerCoreTests",
            dependencies: [
                .product(name: "LedgerCore", package: "LedgerCorePackage"),
            ],
            path: "Tests/LedgerCoreTests"
        ),
    ]
)

