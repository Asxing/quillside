// swift-tools-version: 5.9
import PackageDescription
import Foundation

let developerDirectory = ProcessInfo.processInfo.environment["DEVELOPER_DIR"] ?? "/Library/Developer/CommandLineTools"
let testFrameworks = developerDirectory.hasSuffix("CommandLineTools")
    ? "\(developerDirectory)/Library/Developer/Frameworks"
    : "\(developerDirectory)/Platforms/MacOSX.platform/Developer/Library/Frameworks"

let package = Package(
    name: "Quillside",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Quillside", targets: ["Quillside"])
    ],
    dependencies: [.package(url: "https://github.com/jpsim/Yams.git", exact: "6.0.2")],
    targets: [
        .executableTarget(
            name: "Quillside",
            dependencies: [.product(name: "Yams", package: "Yams")],
            path: "src/Quillside",
            linkerSettings: [
                .linkedLibrary("z")
            ]
        ),
        .testTarget(
            name: "QuillsideTests",
            dependencies: ["Quillside"],
            path: "tests",
            resources: [.copy("Fixtures")],
            swiftSettings: [.unsafeFlags(["-F\(testFrameworks)", "-I\(testFrameworks)", "-Xfrontend", "-disable-cross-import-overlays"])],
            linkerSettings: [.unsafeFlags(["-F\(testFrameworks)", "-Xlinker", "-rpath", "-Xlinker", testFrameworks])]
        )
    ]
)
