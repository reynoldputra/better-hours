// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BetterHoursCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BetterHoursCore", targets: ["BetterHoursCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "BetterHoursCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(
            name: "BetterHoursCoreTests",
            dependencies: ["BetterHoursCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
