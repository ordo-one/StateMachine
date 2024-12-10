// swift-tools-version:5.10

import PackageDescription
import CompilerPluginSupport

let swiftSyntaxVersion = Version("510.0.3")
#if os(macOS) || os(iOS)
let swiftSyntaxRepo = "https://github.com/ordo-one/swift-syntax-xcf"
#else
let swiftSyntaxRepo = "https://github.com/apple/swift-syntax"
#endif

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
    targets: {
        var targets: [Target] = [
            .target(
                name: "StateMachine",
                dependencies: ["StateMachineMacros"],
                path: "Swift/Sources/StateMachine"),
            .macro(
                name: "StateMachineMacros",
                dependencies: makeSwiftSyntaxTargetDependencies(),
                path: "Swift/Sources/StateMachineMacros")
        ]

#if os(Linux)
        targets.append(
            .testTarget(
                name: "StateMachineTests",
                dependencies: {
                    var deps: [Target.Dependency] = [
                        "StateMachine",
                        "StateMachineMacros",
                        "Nimble"
                    ]
#if !os(macOS) && !os(iOS)
                    deps.append(.product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"))
#endif
                    return deps
                }(),
                path: "Swift/Tests/StateMachineTests")
        )
#endif

        return targets
    }()
)

func makeSwiftSyntaxTargetDependencies() -> [PackageDescription.Target.Dependency] {
#if os(macOS) || os(iOS)
    [
        .product(name: "SwiftSyntaxWrapper", package: "swift-syntax-xcf")
    ]
#else
    [
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
    ]
#endif
}
