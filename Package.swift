// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CodexTranslator",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "CodexTranslator", targets: ["CodexTranslator"])
    ],
    targets: [
        .executableTarget(
            name: "CodexTranslator",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon")
            ]
        )
    ]
)
