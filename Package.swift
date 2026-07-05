// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SwitchTab",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WindowSwitcher", targets: ["WindowSwitcher"]),
        .executable(name: "WindowSwitcherTestRunner", targets: ["WindowSwitcherTestRunner"])
    ],
    targets: [
        .target(
            name: "WindowSwitcher",
            path: "WindowSwitcher",
            exclude: [
                "Resources/Info.plist",
                "Resources/WindowSwitcher.entitlements",
                "Resources/MenuBarIcon.svg",
                "Resources/AppIconCandidates",
                "Resources/Assets.xcassets"
            ]
        ),
        .executableTarget(
            name: "WindowSwitcherTestRunner",
            dependencies: ["WindowSwitcher"],
            path: "WindowSwitcherTests"
        )
    ]
)
