// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "CashRunwayCorePackage",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v15),
    ],
    products: [
        .library(name: "CashRunwayCore", targets: ["CashRunwayCore"]),
    ],
    dependencies: [
        .package(path: "../../Vendor/GRDB.swift"),
    ],
    targets: [
        .target(
            name: "CashRunwayCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/CashRunwayCore"
        ),
    ]
)
