// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NativeWhisper",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "NativeWhisper", targets: ["NativeWhisper"])
    ],
    targets: [
        .executableTarget(
            name: "NativeWhisper",
            path: "NativeWhisper",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "NativeWhisperTests",
            dependencies: ["NativeWhisper"],
            path: "NativeWhisperTests"
        )
    ]
)
