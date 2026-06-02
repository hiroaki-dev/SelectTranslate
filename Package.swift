// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SelectTranslate",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "SelectTranslate", targets: ["SelectTranslate"])
    ],
    targets: [
        .executableTarget(
            name: "SelectTranslate",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon")
            ]
        )
    ]
)
