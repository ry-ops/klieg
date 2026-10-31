// swift-tools-version: 6.2
import PackageDescription

let v5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

// KliegKit, KliegServer, the klieg CLI and the self-test build on macOS and Linux, so the agent VMs
// can build and test them. The Klieg app (SwiftUI + SwiftTerm) is macOS-only and builds with the
// Command Line Tools alone; the Xcode app is never needed.
var products: [Product] = [
    .executable(name: "klieg", targets: ["klieg"]),
    .library(name: "KliegKit", targets: ["KliegKit"]),
]
var dependencies: [Package.Dependency] = []
var targets: [Target] = [
    .target(name: "KliegKit", swiftSettings: v5),
    .target(name: "KliegServer", dependencies: ["KliegKit"], swiftSettings: v5),
    .executableTarget(name: "klieg", dependencies: ["KliegKit", "KliegServer"], path: "Sources/KliegCLI", swiftSettings: v5),
    .executableTarget(name: "klieg-selftest", dependencies: ["KliegKit", "KliegServer"], path: "Tests/SelfTest", swiftSettings: v5),
]

#if os(macOS)
products.append(.executable(name: "KliegApp", targets: ["KliegApp"]))
// The in-app terminal. MIT, pinned to an exact release (same as afm-studio).
dependencies.append(.package(url: "https://github.com/migueldeicaza/SwiftTerm", exact: "1.99.1"))
targets.append(.executableTarget(name: "KliegApp",
                                 dependencies: ["KliegKit", "KliegServer", .product(name: "SwiftTerm", package: "SwiftTerm")], path: "Sources/KliegApp",
                                 swiftSettings: v5))
#endif

let package = Package(
    name: "klieg",
    platforms: [.macOS("27.0")],
    products: products,
    dependencies: dependencies,
    targets: targets
)
