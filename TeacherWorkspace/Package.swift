// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TeacherWorkspace",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "TeacherWorkspace",
            dependencies: [
                "llama",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/TeacherWorkspace"
        ),
        .binaryTarget(
            name: "llama",
            path: "vendor/llama.cpp/build-apple/llama.xcframework"
        )
    ]
)
