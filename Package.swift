// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Stats",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Stats",
            path: "Sources/Stats",
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", "Sources/Stats/Info.plist"])
            ]
        )
    ]
)
