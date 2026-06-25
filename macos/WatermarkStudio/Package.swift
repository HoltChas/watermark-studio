// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WatermarkStudio",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "WatermarkStudioMac", targets: ["WatermarkStudioMac"])
    ],
    targets: [
        .executableTarget(name: "WatermarkStudioMac"),
        .testTarget(
            name: "WatermarkStudioMacTests",
            dependencies: ["WatermarkStudioMac"]
        )
    ]
)
