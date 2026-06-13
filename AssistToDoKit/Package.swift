// swift-tools-version: 5.10
import PackageDescription

// Couche app portable partagée par les targets macOS et iOS : sync Toudou, store SwiftData,
// réseau OpenRouter, transcription WhisperKit, EventKit, notifications. Dépend du cœur métier
// AssistToDoCore (Foundation pur). Aucune UI ici (les vues vivent dans chaque target).
let package = Package(
    name: "AssistToDoKit",
    // Minimum du package (la cible app iOS vise iOS 18, réglé dans Xcode).
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "AssistToDoKit", targets: ["AssistToDoKit"])
    ],
    dependencies: [
        .package(path: "../AssistToDoCore"),
        // Même contrainte que le projet Xcode (branch main) pour éviter un conflit de
        // résolution ; la révision exacte reste verrouillée par Package.resolved du projet.
        .package(url: "https://github.com/argmaxinc/WhisperKit", branch: "main")
    ],
    targets: [
        .target(
            name: "AssistToDoKit",
            dependencies: [
                "AssistToDoCore",
                .product(name: "WhisperKit", package: "WhisperKit")
            ]
        ),
        .testTarget(
            name: "AssistToDoKitTests",
            dependencies: ["AssistToDoKit", "AssistToDoCore"]
        )
    ]
)
