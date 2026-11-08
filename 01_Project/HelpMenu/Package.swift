// swift-tools-version: 5.9
import PackageDescription

// HelpMenu — vendored into Stills From Video from 1-macOS/appHELP (2026-11-08).
// Engine only: help window, sidebar, search, markdown renderer. The app owns
// the content (ScreenshotFromVideos/Help/). Re-copy Sources/ from appHELP to pick up fixes.
// Only external dependency is swift-markdown-ui (markdown rendering).
let package = Package(
    name: "HelpMenu",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "HelpMenu", targets: ["HelpMenu"])
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.0")
    ],
    targets: [
        .target(
            name: "HelpMenu",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui")
            ]
        )
    ]
)
