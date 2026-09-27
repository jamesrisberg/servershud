// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "serversHUD",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "serversHUDKit", targets: ["serversHUDKit"]),
        .executable(name: "serversHUD", targets: ["serversHUD"]),
        // Installed as Contents/Helpers/servershud: a distinct product name because serversHUD and
        // servershud would collide on a case-insensitive volume.
        .executable(name: "serversHUDCLI", targets: ["serversHUDCLI"]),
    ],
    dependencies: [
        // Sibling checkout: ~/dev/hudkit next to ~/dev/servershud.
        .package(path: "../hudkit"),
    ],
    targets: [
        // Pure core: the lsof/ps scan, framework guess, dev-only filter, snapshot diff, actions, JSON.
        .target(
            name: "serversHUDKit",
            path: "Sources/serversHUDKit"
        ),
        .executableTarget(
            name: "serversHUD",
            dependencies: ["serversHUDKit", .product(name: "HUDKit", package: "hudkit")],
            path: "Sources/serversHUD",
            // Bundle files, assembled into the .app by hudkit/scripts/hud-build.sh.
            exclude: ["Resources"]
        ),
        // `servershud <command> [key=value ...]`: socket client, scanning directly when the app is not running.
        .executableTarget(
            name: "serversHUDCLI",
            dependencies: ["serversHUDKit", .product(name: "HUDKit", package: "hudkit")],
            path: "Sources/serversHUDCLI"
        ),
        .testTarget(
            name: "serversHUDKitTests",
            dependencies: ["serversHUDKit"],
            path: "Tests/serversHUDKitTests"
        ),
        // Host logic in the app target and the shipped manifest/settings schema/Info.plist.
        .testTarget(
            name: "serversHUDTests",
            dependencies: ["serversHUD", "serversHUDKit", .product(name: "HUDKit", package: "hudkit")],
            path: "Tests/serversHUDTests"
        ),
    ]
)
