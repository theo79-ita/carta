// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Carta",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Carta", targets: ["Carta"])],
    targets: [
        .executableTarget(name: "Carta", resources: [.copy("Resources")])
    ]
)
