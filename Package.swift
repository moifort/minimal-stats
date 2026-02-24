// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Stats",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "Stats",
            path: "Sources/Stats",
            exclude: ["Info.plist"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", "Sources/Stats/Info.plist"])
            ]
        )
    ]
)
