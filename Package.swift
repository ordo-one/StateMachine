// swift-tools-version:6.1

import CompilerPluginSupport
import class Foundation.ProcessInfo
import PackageDescription

let swiftSyntaxVersion = Version("601.0.1")

func useXcFrameworksSwiftSyntax() -> Bool {
    #if os(iOS)
        return true
    #else
        #if swift(>=6.2)
            return false
        #elseif os(Linux)
            return false
        #else
            let useSwiftSyntaxXcf = (ProcessInfo.processInfo.environment["ORDO_USE_SWIFT_SYNTAX_XCF"] ?? "true") == "true"
            if !useSwiftSyntaxXcf {
                print("Make sure to pass build flag `--enable-experimental-prebuilts` to avoid building SwiftSyntax")
            }
            return useSwiftSyntaxXcf
        #endif
    #endif
}

func makeDependencies() -> [Package.Dependency] {
    let xcFrameworksRepo = "https://github.com/ordo-one/swift-syntax-xcframeworks"
    let officialSyntaxRepo = "https://github.com/swiftlang/swift-syntax"
    let syntaxUrl = useXcFrameworksSwiftSyntax() ? xcFrameworksRepo : officialSyntaxRepo
    return [
        .package(url: syntaxUrl, exact: swiftSyntaxVersion),
        .package(url: "https://github.com/Quick/Nimble.git", from: "13.2.0"),
    ]
}

func makeSwiftSyntaxTargetDependencies() -> [PackageDescription.Target.Dependency] {
    let xcFrameworkDependencies: [PackageDescription.Target.Dependency] = [
        .product(name: "SwiftSyntaxWrapper", package: "swift-syntax-xcframeworks"),
    ]
    let officialSyntaxDependencies: [PackageDescription.Target.Dependency] = [
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
    ]
    return useXcFrameworksSwiftSyntax() ? xcFrameworkDependencies : officialSyntaxDependencies
}

func makeSwiftSyntaxTestDependencies() -> PackageDescription.Target.Dependency {
    let xcFrameworkDependencies: PackageDescription.Target.Dependency =
        .product(name: "SwiftSyntaxWrapper", package: "swift-syntax-xcframeworks")
    let officialSyntaxDependencies: PackageDescription.Target.Dependency =
        .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax")
    return useXcFrameworksSwiftSyntax() ? xcFrameworkDependencies : officialSyntaxDependencies
}

let package = Package(
    name: "StateMachine",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .visionOS(.v2)
    ],
    products: [
        .library(
            name: "StateMachine",
            targets: ["StateMachine"]
        ),
    ],
    dependencies: makeDependencies(),
    targets: [
        .target(
            name: "StateMachine",
            dependencies: ["StateMachineMacros"],
            path: "Swift/Sources/StateMachine"
        ),
        .macro(
            name: "StateMachineMacros",
            dependencies: makeSwiftSyntaxTargetDependencies(),
            path: "Swift/Sources/StateMachineMacros"
        ),
        .testTarget(
            name: "StateMachineTests",
            dependencies: [
                "StateMachine",
                "StateMachineMacros",
                makeSwiftSyntaxTestDependencies(),
                "Nimble",
            ],
            path: "Swift/Tests/StateMachineTests"
        ),
    ]
)
