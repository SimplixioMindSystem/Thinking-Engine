// swift-tools-version: 5.9
// Package.swift – allows building the shared library with SwiftPM

import PackageDescription

let package = Package(
    name: "CortexOS",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "CortexOSKit",
            targets: ["CortexOSKit"]
        ),
    ],
    targets: [
        .target(
            name: "CortexOSKit",
            path: "CortexOSApp/Shared",
            exclude: ["Assets.xcassets", "CortexOSApp.swift", "PrivacyInfo.xcprivacy"],
            sources: [
                "Components",
                "Design",
                "Models",
                "Services",
                "Views",
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        .testTarget(
            name: "CortexOSKitTests",
            dependencies: ["CortexOSKit"],
            path: "Tests/CortexOSKitTests"
        ),
    ]
)
