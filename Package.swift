// swift-tools-version:6.3

import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "StateMachine",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .visionOS(.v26)
    ],
    products: [
        .library(
            name: "StateMachine",
            targets: ["StateMachine"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax", from: "603.0.0"),
        .package(url: "https://github.com/Quick/Nimble.git", from: "13.2.0"),
    ],
    targets: [
        .target(
            name: "StateMachine",
            dependencies: ["StateMachineMacros"],
            path: "Swift/Sources/StateMachine"
        ),
        .macro(
            name: "StateMachineMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ],
            path: "Swift/Sources/StateMachineMacros"
        ),
        .testTarget(
            name: "StateMachineTests",
            dependencies: [
                "StateMachine",
                "StateMachineMacros",
                "Nimble",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ],
            path: "Swift/Tests/StateMachineTests"
        ),
    ]
)
