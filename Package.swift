// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "CashRunwayWorkspace",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    dependencies: [
        .package(path: "Vendor/GRDB.swift"),
        .package(url: "https://github.com/CoreOffice/CoreXLSX.git", from: "0.14.2"),
    ],
    targets: [
        .target(
            name: "CashRunwayCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "CoreXLSX", package: "CoreXLSX"),
            ],
            path: "Sources/CashRunwayCore"
        ),
        .testTarget(
            name: "CashRunwayCoreTests",
            dependencies: ["CashRunwayCore"],
            path: "Tests/CashRunwayCoreTests",
            exclude: ["Fixtures"]
        ),
    ]
)

