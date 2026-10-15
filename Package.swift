// swift-tools-version: 6.4
import PackageDescription
let package = Package(
    name: "NetworkToyCore",
    platforms: [.macOS(.v27)],
    products: [.library(name: "NetworkToyCore", targets: ["NetworkToyCore"])],
    targets: [
        .target(name: "NetworkToyCore", path: "NetworkToy/Simulation", exclude: ["NetworkStore.swift"]),
        .testTarget(name: "NetworkToyCoreTests", dependencies: ["NetworkToyCore"], path: "Tests")
    ],
    swiftLanguageModes: [.v6]
)
