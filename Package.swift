// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ComposeCommandClaimKit",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9)
    ],
    products: [
        .library(name: "ComposeCommandClaimKit", targets: ["ComposeCommandClaimKit"]),
        .executable(name: "ComposeCommandClaimDemo", targets: ["ComposeCommandClaimDemo"])
    ],
    dependencies: [
        .package(url: "https://github.com/rajatslakhina/entrypoint-claim-kit.git", from: "1.0.1"),
        .package(url: "https://github.com/rajatslakhina/dockerfile-claim-kit.git", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "ComposeCommandClaimKit",
            dependencies: [
                .product(name: "EntrypointClaimKit", package: "entrypoint-claim-kit"),
                .product(name: "DockerfileClaimKit", package: "dockerfile-claim-kit")
            ]
        ),
        .executableTarget(
            name: "ComposeCommandClaimDemo",
            dependencies: ["ComposeCommandClaimKit"]
        ),
        .testTarget(
            name: "ComposeCommandClaimKitTests",
            dependencies: [
                "ComposeCommandClaimKit",
                .product(name: "EntrypointClaimKit", package: "entrypoint-claim-kit"),
                .product(name: "DockerfileClaimKit", package: "dockerfile-claim-kit")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
