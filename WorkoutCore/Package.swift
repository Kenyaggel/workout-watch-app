// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WorkoutCore",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14)
    ],
    products: [
        .library(name: "WorkoutCore", targets: ["WorkoutCore"])
    ],
    targets: [
        .target(name: "WorkoutCore"),
        .testTarget(name: "WorkoutCoreTests", dependencies: ["WorkoutCore"])
    ]
)
