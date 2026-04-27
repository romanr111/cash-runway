// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "LedgerCorePackage",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v15),
    ],
    products: [
        .library(name: "LedgerCore", targets: ["LedgerCore"]),
    ],
    dependencies: [
        .package(path: "../../Vendor/GRDB.swift"),
    ],
    targets: [
        .target(
            name: "LedgerCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/LedgerCore"
        ),
    ]
)
