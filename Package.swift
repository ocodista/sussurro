// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Sussurro",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Sussurro", targets: ["SussurroApp"])
    ],
    targets: [
        .executableTarget(
            name: "SussurroApp",
            path: "Sources/SussurroApp"
        )
    ]
)
