// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Sussurro",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Sussurro", targets: ["SussurroApp"]),
        .executable(name: "sussurro-mcp", targets: ["SussurroMCP"]),
        .library(name: "SussurroCore", targets: ["SussurroCore"])
    ],
    targets: [
        .target(name: "SussurroCore"),
        .executableTarget(
            name: "SussurroApp",
            dependencies: ["SussurroCore"],
            path: "Sources/SussurroApp",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "SussurroAppTests",
            dependencies: ["SussurroApp"]
        ),
        .executableTarget(name: "SussurroMCP", dependencies: ["SussurroCore"]),
        .testTarget(name: "SussurroCoreTests", dependencies: ["SussurroCore"])
    ]
)
