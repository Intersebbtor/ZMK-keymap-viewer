import SwiftUI
import AppKit

class FloatingPanel: NSPanel {
    init(view: AnyView, contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .resizable, .titled, .fullSizeContentView],
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
        
        // Configuration de la sauvegarde automatique de la position
        self.setFrameAutosaveName("ZMKKeymapHUD")
        
        // Tenter de restaurer la position précédente, sinon utiliser le défaut
        _ = self.setFrameUsingName("ZMKKeymapHUD")
        
        let hostingView = NSHostingView(rootView: view)
        self.contentView = hostingView
    }
}
