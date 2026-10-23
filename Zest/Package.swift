// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Zest",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Zest",
            path: "Sources/Zest",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AVKit"),
                .linkedFramework("PDFKit"),
                .linkedFramework("QuickLookThumbnailing"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("Vision"),
                .linkedFramework("CoreImage"),
                .linkedFramework("UniformTypeIdentifiers"),
            ]
        )
    ]
)
