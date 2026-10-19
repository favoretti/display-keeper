// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "display-keeper",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "display-keeper", targets: ["display-keeper"]),
        .executable(name: "DisplayKeeper", targets: ["DisplayKeeper"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .target(name: "DisplayKeeperCore", linkerSettings: [.linkedFramework("IOKit")]),
        .executableTarget(name: "display-keeper", dependencies: ["DisplayKeeperCore"]),
        .executableTarget(
            name: "DisplayKeeper",
            dependencies: ["DisplayKeeperCore", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "DisplayKeeperCoreTests", dependencies: ["DisplayKeeperCore"]),
    ],
    swiftLanguageModes: [.v5]
)
