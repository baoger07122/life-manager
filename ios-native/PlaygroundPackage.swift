// swift-tools-version: 5.9

// This manifest mirrors the structure created by Swift Playgrounds on iPad.

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "HomeOSNativePreview",
    platforms: [
        .iOS("17.0")
    ],
    products: [
        .iOSApplication(
            name: "Home OS 原生预览",
            targets: ["AppModule"],
            displayVersion: "0.1.22",
            bundleVersion: "20",
            appIcon: .placeholder(icon: .box),
            accentColor: .presetColor(.blue),
            supportedDeviceFamilies: [
                .pad
            ],
            supportedInterfaceOrientations: [
                .portrait
            ]
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: ".",
            swiftSettings: [
                .define("PLAYGROUND_PREVIEW")
            ]
        )
    ]
)
