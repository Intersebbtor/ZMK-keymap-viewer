import SwiftUI
import AppKit

class FloatingPanel: NSPanel {
    init(view: AnyView, contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            // No .resizable: the native border only worked at the bottom corners
            // of this transparent window. HUDView adds its own resize zones on all
            // edges and corners (WindowResizeEdges).
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = true
        self.isFloatingPanel = true
        self.level = .floating
        self.isReleasedWhenClosed = false
        self.standardWindowButton(.closeButton)?.isHidden = true
        self.standardWindowButton(.miniaturizeButton)?.isHidden = true
        self.standardWindowButton(.zoomButton)?.isHidden = true
        
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.minSize = NSSize(width: 280, height: 140)

        // Configuration for automatic position saving
        self.setFrameAutosaveName("ZMKKeymapHUD")
        
        // Attempt to restore previous position, otherwise use default
        _ = self.setFrameUsingName("ZMKKeymapHUD")
        
        let hostingView = NSHostingView(rootView: view)
        self.contentView = hostingView
    }
}
