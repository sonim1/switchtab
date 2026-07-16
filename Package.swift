// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SwitchTab",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SwitchTab", targets: ["SwitchTab"]),
        .executable(name: "SwitchTabTestRunner", targets: ["SwitchTabTestRunner"])
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
        .executableTarget(
            name: "SwitchTabTestRunner",
            dependencies: ["SwitchTab"],
            path: "SwitchTabTests"
        )
    ]
)
