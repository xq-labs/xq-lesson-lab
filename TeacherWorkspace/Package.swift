// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TeacherWorkspace",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "TeacherWorkspace",
            path: "Sources/TeacherWorkspace"
        )
    ]
)
