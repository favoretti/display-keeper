// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "display-keeper",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "display-keeper", targets: ["display-keeper"]),
        .executable(name: "DisplayKeeper", targets: ["DisplayKeeper"]),
    ],
    targets: [
        .target(name: "DisplayKeeperCore", linkerSettings: [.linkedFramework("IOKit")]),
        .executableTarget(name: "display-keeper", dependencies: ["DisplayKeeperCore"]),
        .executableTarget(name: "DisplayKeeper", dependencies: ["DisplayKeeperCore"]),
        .testTarget(name: "DisplayKeeperCoreTests", dependencies: ["DisplayKeeperCore"]),
    ],
    swiftLanguageModes: [.v5]
)
