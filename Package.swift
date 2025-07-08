// swift-tools-version:5.10

import PackageDescription
import CompilerPluginSupport

let swiftSyntaxVersion = Version("601.0.1")
let swiftSyntaxRepo = "https://github.com/swiftlang/swift-syntax"

let package = Package(
    name: "StateMachine",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .tvOS(.v13),
        .watchOS(.v5),
    ],
    products: [
        .library(
            name: "StateMachine",
            targets: ["StateMachine"]),
    ],
    dependencies: [
        .package(url: swiftSyntaxRepo, from: swiftSyntaxVersion),
        .package(url: "https://github.com/Quick/Nimble.git", from: "13.2.0"),
    ],
    targets: [
        .target(
            name: "StateMachine",
            dependencies: ["StateMachineMacros"],
            path: "Swift/Sources/StateMachine"),
        .macro(
            name: "StateMachineMacros",
            dependencies: makeSwiftSyntaxTargetDependencies(),
            path: "Swift/Sources/StateMachineMacros"),
        .testTarget(
            name: "StateMachineTests",
            dependencies: [
                "StateMachine",
                "StateMachineMacros",
                makeSwiftSyntaxTestDependencies(),
                "Nimble",
            ],
            path: "Swift/Tests/StateMachineTests"),
    ]
)

func makeSwiftSyntaxTargetDependencies() -> [PackageDescription.Target.Dependency] {
    [
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
    ]
}

func makeSwiftSyntaxTestDependencies() -> PackageDescription.Target.Dependency {
    .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax")
}
