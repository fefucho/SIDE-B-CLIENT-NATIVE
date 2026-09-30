// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SideBCore",
    platforms: [
        .macOS(.v14) // Apuntamos a macOS moderno
    ],
    products: [
        .library(
            name: "SideBCore",
            targets: ["SideBCore", "SideBCoreXCFramework"]
        ),
    ],
    targets: [
        .target(
            name: "SideBCore",
            dependencies: ["SideBCoreXCFramework"],
            path: "Sources/SideBCore", // Aquí irán los archivos .swift generados por UniFFI
            linkerSettings: [
                .linkedFramework("SystemConfiguration")
            ]
        ),
        .binaryTarget(
            name: "SideBCoreXCFramework",
            path: "../SideBCore.xcframework" // El xcframework compilado
        )
    ]
)
