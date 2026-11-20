// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "TypingPractice",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(
            name: "TypingPractice",
            path: "Sources/TypingPractice"
        )
    ]
)
