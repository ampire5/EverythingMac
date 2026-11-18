// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "EverythingMac", platforms: [.macOS(.v14)],
    products: [
        .executable(name: "EverythingMac", targets: ["EverythingMac"]),
        .library(name: "EverythingCore", targets: ["EverythingCore"]),
        .library(name: "EverythingSearchUI", targets: ["EverythingSearchUI"])
    ],
    targets: [
        .target(name: "EverythingCore"),
        .target(name: "EverythingSearchUI", dependencies: ["EverythingCore"]),
        .executableTarget(name: "EverythingMac", dependencies: ["EverythingCore", "EverythingSearchUI"]),
        .testTarget(name: "EverythingCoreTests", dependencies: ["EverythingCore"]),
        .testTarget(name: "EverythingMacTests", dependencies: ["EverythingMac", "EverythingSearchUI"])
    ], swiftLanguageModes: [.v6]
)
