// swift-tools-version: 5.9
// albedo_flutter macOS FFI plugin: bundles the albedo dynamic xcframework and
// a C forwarder (kept for symmetry with iOS; the dylib is embedded whole so
// dead-stripping is not a concern here).
import PackageDescription

let package = Package(
    name: "albedo_flutter",
    platforms: [.macOS("10.15")],
    products: [
        .library(name: "albedo-flutter", targets: ["albedo_flutter"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "albedo_flutter",
            dependencies: [
                .target(name: "albedo"),
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            path: "Sources/albedo_flutter"
        ),
        .binaryTarget(
            name: "albedo",
            path: "../Frameworks/albedo.xcframework"
        )
    ]
)
