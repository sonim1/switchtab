// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SwitchTab",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SwitchTab", targets: ["SwitchTab"])
    ],
    targets: [
        .target(
            name: "SwitchTab",
            path: "SwitchTab",
            exclude: [
                "Resources/Info.plist",
                "Resources/SwitchTab.entitlements",
                "Resources/MenuBarIcon.svg",
                "Resources/AppIconCandidates",
                "Resources/Assets.xcassets"
            ]
        ),
        .testTarget(
            name: "SwitchTabTests",
            dependencies: ["SwitchTab"],
            path: "SwitchTabTests"
        )
    ]
)
