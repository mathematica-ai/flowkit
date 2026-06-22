// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FlowKit",
    platforms: [.macOS(.v15), .iOS(.v17)],
    products: [
        .library(name: "FlowKit", targets: ["FlowKit"]),
        .executable(name: "runflow", targets: ["runflow"]),
        .executable(name: "FlowDemo", targets: ["FlowDemo"]),
    ],
    targets: [
        .target(
            name: "FlowKit",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "runflow",
            dependencies: ["FlowKit"]
        ),
        .executableTarget(
            name: "FlowDemo",
            dependencies: ["FlowKit"]
        ),
        .testTarget(
            name: "FlowKitTests",
            dependencies: ["FlowKit"]
        ),
    ]
)
