// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SideB",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(
            name: "SideB",
            targets: ["SideB"]
        ),
        .library(
            name: "SideBCore",
            targets: ["SideBCore", "SideBCoreXCFramework"]
        )
    ],
    targets: [
        .executableTarget(
            name: "SideB",
            dependencies: [
                "SideBCore"
            ],
            path: "Sources/SideB",
            swiftSettings: [
                .enableExperimentalFeature("IsolatedDeinit")
            ]
        ),
        .target(
            name: "SideBCore",
            dependencies: ["SideBCoreXCFramework"],
            path: "SideBCore/Sources/SideBCore",
            linkerSettings: [
                .linkedFramework("SystemConfiguration")
            ]
        ),
        .binaryTarget(
            name: "SideBCoreXCFramework",
            path: "SideBCore.xcframework"
        ),
        .testTarget(
            name: "SideBTests",
            dependencies: ["SideB", "SideBCore"],
            path: "Tests/SideBTests"
        )
    ]
)
