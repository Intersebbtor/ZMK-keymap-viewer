// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ZMKKeymapViewer",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ZMKKeymapViewer", targets: ["ZMKKeymapViewerApp"])
    ],
    targets: [
        .executableTarget(
            name: "ZMKKeymapViewerApp",
            path: ".",
            exclude: ["README.md", "AppDelegate.swift", "Sources", "Tests", "ZMK Keymap Viewer.app"],
            sources: [
                "ZMKKeymapViewer.swift",
                "ContentView.swift",
                "KeymapParser.swift",
                "KeymapViewModel.swift",
                "FileMonitor.swift"
            ]
        )
    ]
)
