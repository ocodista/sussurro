// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CustomSTT",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "CustomSTT", targets: ["CustomSTTApp"])
    ],
    targets: [
        .executableTarget(
            name: "CustomSTTApp",
            path: "Sources/CustomSTTApp"
        )
    ]
)
