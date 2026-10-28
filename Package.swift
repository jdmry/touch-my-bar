// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TouchMyBar",
    platforms: [.macOS(.v13)],
    targets: [
        // Declarations for the undocumented DFRFoundation / NSTouchBar SPI
        // that lets an app own the Touch Bar system-wide.
        .target(
            name: "TouchBarPrivate",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "TouchMyBar",
            dependencies: ["TouchBarPrivate"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", "/System/Library/PrivateFrameworks",
                    "-framework", "DFRFoundation",
                ])
            ]
        ),
    ]
)
