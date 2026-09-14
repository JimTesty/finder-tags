// swift-tools-version: 5.5
import PackageDescription

let package = Package(
    name: "tag",
    platforms: [.macOS(.v11)],
    products: [
        .executable(name: "tag", targets: ["tag"]),
    ],
    targets: [
        .executableTarget(name: "tag"),
    ]
)
