// swift-tools-version: 6.2
import PackageDescription

let strict: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
]

let package = Package(
    name: "VaasiKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "VaasiCore", targets: ["VaasiCore"]),
    ],
    targets: [
        .target(
            name: "VaasiCore",
            swiftSettings: strict
        ),
        .testTarget(
            name: "VaasiCoreTests",
            dependencies: ["VaasiCore"],
            swiftSettings: strict
        ),
    ]
)
