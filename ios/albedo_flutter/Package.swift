// swift-tools-version: 5.9
// albedo_flutter iOS FFI plugin: bundles the albedo static xcframework and a
// C forwarder that forces the linker to keep albedo's symbols (otherwise the
// static archive would be dead-stripped and dart:ffi would find nothing).
import PackageDescription

let package = Package(
    name: "albedo_flutter",
    platforms: [.iOS("13.0")],
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
