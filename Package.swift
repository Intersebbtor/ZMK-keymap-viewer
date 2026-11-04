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
            exclude: ["README.md", "scripts", "Tests", "test_comments.swift"],
            sources: [
                "ZMKKeymapViewer.swift",
                "AppDelegate.swift",
                "ContentView.swift",
                "KeymapParser.swift",
                "KeymapViewModel.swift",
                "FileMonitor.swift",
                "FloatingPanel.swift",
                "HUDView.swift",
                "GlobalShortcutManager.swift",
                "PDFExporter.swift",
                "LiveLayer.swift",
                "LiveLayerMonitor.swift",
                "WindowControls.swift",
                "SplitKeyboardIcon.swift",
                "StudioProtocol.swift",
                "StudioClient.swift",
                "StudioKeymap.swift",
                "KeyCharacters.swift",
                "FirmwareSetup.swift",
                "FirmwareEdits.swift",
                "FirmwareSetupView.swift",
                "SetupView.swift"
            ]
        ),
        .testTarget(
            name: "ZMKKeymapViewerTests",
            dependencies: ["ZMKKeymapViewerApp"],
            path: "Tests"
        )
    ]
)
