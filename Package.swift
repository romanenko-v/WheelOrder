// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "WheelOrder",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "WheelOrder", targets: ["WheelOrder"])
    ],
    targets: [
        .executableTarget(
            name: "WheelOrder",
            path: "WheelOrder"
        )
    ]
)
