// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LangflowKit",
    platforms: [.macOS(.v15), .iOS(.v17)],
    products: [
        .library(name: "LangflowKit", targets: ["LangflowKit"]),
        .executable(name: "runflow", targets: ["runflow"]),
        .executable(name: "LangflowDemo", targets: ["LangflowDemo"]),
    ],
    targets: [
        .target(
            name: "LangflowKit",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "runflow",
            dependencies: ["LangflowKit"]
        ),
        .executableTarget(
            name: "LangflowDemo",
            dependencies: ["LangflowKit"]
        ),
        .testTarget(
            name: "LangflowKitTests",
            dependencies: ["LangflowKit"]
        ),
    ]
)
