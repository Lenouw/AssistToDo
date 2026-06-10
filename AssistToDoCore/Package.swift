// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AssistToDoCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AssistToDoCore", targets: ["AssistToDoCore"])
    ],
    targets: [
        .target(name: "AssistToDoCore"),
        .testTarget(name: "AssistToDoCoreTests", dependencies: ["AssistToDoCore"])
    ]
)
