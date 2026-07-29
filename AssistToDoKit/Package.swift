// swift-tools-version: 5.10
import PackageDescription

// Couche app portable partagée par les targets macOS et iOS : sync Toudou, store SwiftData,
// réseau OpenRouter, transcription whisper.cpp (ggml + Metal), EventKit, notifications. Dépend du
// cœur métier AssistToDoCore (Foundation pur). Aucune UI ici (les vues vivent dans chaque target).
let package = Package(
    name: "AssistToDoKit",
    // Minimum du package (la cible app iOS vise iOS 18, réglé dans Xcode).
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "AssistToDoKit", targets: ["AssistToDoKit"])
    ],
    dependencies: [
        .package(path: "../AssistToDoCore")
    ],
    targets: [
        // Moteur de transcription whisper.cpp (ggml + Metal) : xcframework prébuilt hébergé sur notre
        // GitHub. Chargement du modèle par mmap → quasi instantané, aucune compilation CoreML/ANE.
        .binaryTarget(
            name: "whisper",
            url: "https://github.com/Lenouw/AssistToDo/releases/download/whisper-xcframework-v1/whisper.xcframework.zip",
            checksum: "c84de341776e9ef87af7bf3d467c05ae841f31342e39fb6fe8d2f8aadbaa3638"
        ),
        .target(
            name: "AssistToDoKit",
            dependencies: [
                "AssistToDoCore",
                "whisper"
            ]
        ),
        .testTarget(
            name: "AssistToDoKitTests",
            dependencies: ["AssistToDoKit", "AssistToDoCore"]
        )
    ]
)
