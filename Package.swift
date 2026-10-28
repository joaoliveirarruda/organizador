// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Organizador",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Organizador", targets: ["Organizador"]),
        .library(name: "OrganizadorCore", targets: ["OrganizadorCore"]),
    ],
    targets: [
        // Pure Foundation logic (models, timer, stats, storage). No UI, testable anywhere.
        .target(name: "OrganizadorCore"),
        // The macOS app (SwiftUI).
        .executableTarget(name: "Organizador", dependencies: ["OrganizadorCore"]),
        .testTarget(name: "OrganizadorCoreTests", dependencies: ["OrganizadorCore"]),
    ]
)
