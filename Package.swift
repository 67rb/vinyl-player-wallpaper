// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VinylWallpaper",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "VinylWallpaper",
            path: "Sources/VinylWallpaper"
        )
    ]
)
