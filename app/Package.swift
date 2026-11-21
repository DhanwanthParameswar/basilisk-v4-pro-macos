// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Basilisk",
    platforms: [.macOS("27.0")],
    targets: [
        .executableTarget(
            name: "Basilisk",
            path: "Sources/Basilisk",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreBluetooth"),
                .linkedFramework("ServiceManagement")
            ]
        )
    ]
)
