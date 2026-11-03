import SwiftUI
import AppKit

let appVersion = "1.5.0"
let githubRepo = "Intersebbtor/ZMK-keymap-viewer"

@main
struct ZMKKeymapViewerApp: App {
    // Created lazily by SwiftUI once the app is set up. Creating it in init()
    // registers event monitors too early and leaves the menu unclickable.
    @StateObject private var appState = AppState()

    init() {
        print("[App] ZMKKeymapViewer starting...")

        // Minimal startup configuration
        NSSetUncaughtExceptionHandler { exception in
            print("[App] CRASH: \(exception)")
        }
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(appState)
                .environmentObject(appState.keymapViewModel)
                .onAppear {
                    appState.setupHUDPanel(with: appState.keymapViewModel)
                }
        } label: {
            MenuBarIcon(appState: appState, viewModel: appState.keymapViewModel)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Keyboard icon, or the live layer number when not on the base layer.
/// Always a single fixed-width Image, so the status item keeps its size.
struct MenuBarIcon: View {
    @ObservedObject var appState: AppState
    @ObservedObject var viewModel: KeymapViewModel

    var body: some View {
        Image(systemName: MenuBarSymbol.name(
            liveIndex: viewModel.layerSelection.liveIndex,
            showLayer: appState.showLayerInMenuBar
        ))
    }
}

class AppState: ObservableObject {
    // Keep a static reference for global shortcut only
    private static var instance: AppState?
    
    @Published var recentKeymaps: [String] = []
    @Published var updateAvailable: String? = nil
    @Published var isCheckingUpdate = false
    @Published var isUpToDate = false
    
    // HUD Settings
    @AppStorage("isHUDModeEnabled") var isHUDModeEnabled = false
    @AppStorage("hudOpacity") var hudOpacity: Double = 0.9
    @AppStorage("hudUseMaterial") var hudUseMaterial = true
    @AppStorage("hudTimeout") var hudTimeout: Double = 3.0
    
    // Live Layer Settings
    @AppStorage("followLiveLayer") var followLiveLayer = true {
        didSet { if followLiveLayer { syncToLiveLayer() } }
    }
    @AppStorage("showLayerInMenuBar") var showLayerInMenuBar = true

    // Export Settings
    @AppStorage("exportDirectory") var exportDirectory: String = "Desktop"
    
    // Global Shortcut Settings
    @AppStorage("shortcutKeyCode") var shortcutKeyCode: Int = 40 // 'K'
    @AppStorage("shortcutModifiers") var shortcutModifiers: Int = 768 // cmdKey | shiftKey (256 | 512)
    
    @Published var isHUDInactive = false
    @Published var isSettingsVisible = false
    private var activityTimer: Timer?
    private var eventMonitor: Any?
    
    private let recentKeymapsKey = "recentKeymaps"
    private let maxRecentKeymaps = 5
    
    var floatingPanel: FloatingPanel?

    let keymapViewModel = KeymapViewModel()

    // Live layer from the keyboard (zmk-keypeek-layer-notifier firmware module)
    private let liveLayerMonitor = LiveLayerMonitor()
    @Published private(set) var liveDeviceName: String?

    init() {
        AppState.instance = self
        loadRecentKeymaps()
        setupActivityMonitor()
        setupGlobalShortcut()
        setupLiveLayerMonitor()
        
        // Check for updates silently on launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.checkForUpdates()
        }
        
        // Load the keymap and set up the HUD at launch instead of on first
        // menu open, so the live layer and the HUD work right away
        if let mostRecent = recentKeymaps.first {
            keymapViewModel.loadKeymap(from: mostRecent)
        }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.setupHUDPanel(with: self.keymapViewModel)
        }
    }
    
    func setupGlobalShortcut() {
        GlobalShortcutManager.shared.setup(
            keyCode: UInt32(shortcutKeyCode),
            modifiers: UInt32(shortcutModifiers)
        ) {
            DispatchQueue.main.async {
                print("[Shortcut] Hotkey triggered!")
                AppState.instance?.toggleHUD()
            }
        }
    }
    
    func setupLiveLayerMonitor() {
        liveLayerMonitor.onConnectionChange = { [weak self] connected in
            guard let self = self else { return }
            self.liveDeviceName = self.liveLayerMonitor.connectedDeviceName
            if connected {
                // The firmware only reports changes, so assume the base layer
                // until the first one arrives
                self.handleLiveLayer(0)
            } else {
                self.keymapViewModel.clearLiveLayer()
            }
        }
        liveLayerMonitor.onPacket = { [weak self] packet in
            guard let self = self else { return }
            switch packet {
            case let .layerState(defaultLayers, activeLayers):
                let layer = ActiveLayerResolver.highestLayer(activeLayers: activeLayers, defaultLayers: defaultLayers)
                self.handleLiveLayer(layer)
            case let .keyEvent(position, pressed):
                self.keymapViewModel.setKey(position: position, pressed: pressed)
                // Every key press keeps the HUD awake, not only layer changes,
                // so it doesn't light up seemingly at random while typing.
                // The timeout starts once the last held key is released.
                if pressed || self.keymapViewModel.pressedPositions.isEmpty {
                    self.wakeHUD()
                }
            }
        }
        liveLayerMonitor.start()
    }

    private func handleLiveLayer(_ index: Int) {
        print("[LiveLayer] Active layer: \(index)")
        keymapViewModel.applyLiveLayer(index, follow: followLiveLayer)
        wakeHUD()
    }

    /// Wake a faded HUD; it fades again after the usual timeout
    private func wakeHUD() {
        if followLiveLayer, floatingPanel?.isVisible == true {
            resetInactivity()
        }
    }

    private func syncToLiveLayer() {
        guard let live = keymapViewModel.layerSelection.liveIndex else { return }
        keymapViewModel.applyLiveLayer(live, follow: true)
    }

    func updateShortcut(keyCode: Int, modifiers: Int) {
        shortcutKeyCode = keyCode
        shortcutModifiers = modifiers
        setupGlobalShortcut()
    }
    
    func setupActivityMonitor() {
        // Global monitor: Only wake HUD when mouse hovers over the panel
        // Keystrokes in other apps should NOT wake the HUD
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .leftMouseDragged]) { [weak self] event in
            guard let self = self else { return }
            
            // Check if mouse is over the HUD panel
            if let panel = self.floatingPanel, 
               panel.isVisible,
               panel.frame.contains(NSEvent.mouseLocation) {
                // Pause timer while hovering/dragging over panel
                self.pauseInactivityTimer()
            } else {
                // Resume timer when mouse leaves panel
                self.resumeInactivityTimer()
            }
        }
        
        // Local monitor: Wake on any interaction within the app itself
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .mouseMoved, .leftMouseDown, .leftMouseDragged]) { [weak self] event in
            guard let self = self else { return event }
            
            if event.type == .mouseMoved || event.type == .leftMouseDragged {
                // Keep timer paused while interacting with the panel
                if let panel = self.floatingPanel, 
                   panel.isVisible,
                   panel.frame.contains(NSEvent.mouseLocation) {
                    self.pauseInactivityTimer()
                }
            } else {
                self.resetInactivity()
            }
            return event
        }
        
        resetInactivity()
        
        // Check for accessibility permissions once at startup (informational)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let accessEnabled = AXIsProcessTrustedWithOptions(options)
        print("[App] Accessibility status: \(accessEnabled)")
    }
    
    private var isTimerPaused = false
    
    func pauseInactivityTimer() {
        DispatchQueue.main.async {
            self.isHUDInactive = false
            self.activityTimer?.invalidate()
            self.isTimerPaused = true
        }
    }
    
    func resumeInactivityTimer() {
        DispatchQueue.main.async {
            guard self.isTimerPaused else { return }
            self.isTimerPaused = false
            self.resetInactivity()
        }
    }
    
    func resetInactivity(caller: String = #function) {
        DispatchQueue.main.async {
            guard !self.isTimerPaused else { return }
            
            self.isHUDInactive = false
            self.activityTimer?.invalidate()
            
            guard self.hudTimeout > 0 else { return }
            // Don't fade while a key is held, e.g. a layer key: the user is
            // probably looking for a key on that layer
            guard self.keymapViewModel.pressedPositions.isEmpty else { return }
            
            self.activityTimer = Timer.scheduledTimer(withTimeInterval: self.hudTimeout, repeats: false) { [weak self] _ in
                withAnimation(.easeInOut(duration: 1.0)) {
                    self?.isHUDInactive = true
                }
            }
        }
    }
    
    func toggleHUD() {
        if let panel = floatingPanel {
            if panel.isVisible {
                disableHUD()
            } else {
                resetInactivity()
                panel.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                isHUDModeEnabled = true
            }
        } else {
            // If the panel is not ready yet, force it
            setupHUDPanel(with: keymapViewModel)
            if let panel = floatingPanel {
                panel.makeKeyAndOrderFront(nil)
                isHUDModeEnabled = true
            }
        }
    }
    
    func disableHUD() {
        if let panel = floatingPanel {
            panel.orderOut(nil)
        }
        isHUDModeEnabled = false
    }
    
    func setupFloatingPanel(with view: AnyView) {
        if floatingPanel == nil {
            let panel = FloatingPanel(
                view: view,
                contentRect: NSRect(x: 100, y: 100, width: 700, height: 400)
            )
            floatingPanel = panel
            
            if isHUDModeEnabled {
                panel.makeKeyAndOrderFront(nil)
            }
        }
    }
    
    func setupHUDPanel(with keymapViewModel: KeymapViewModel) {
        let hudView = HUDView().environmentObject(self).environmentObject(keymapViewModel)
        self.setupFloatingPanel(with: AnyView(hudView))
    }
    
    // Helper to reset size to current layout if needed
    func resetHUDSize() {
        // This can be called from UI to snap back to ideal size
    }
    
    func loadRecentKeymaps() {
        if let saved = UserDefaults.standard.array(forKey: recentKeymapsKey) as? [String] {
            recentKeymaps = saved
        }
    }
    
    func addRecentKeymap(_ path: String) {
        // Remove if already exists
        recentKeymaps.removeAll { $0 == path }
        // Add to front
        recentKeymaps.insert(path, at: 0)
        // Keep only max items
        if recentKeymaps.count > maxRecentKeymaps {
            recentKeymaps = Array(recentKeymaps.prefix(maxRecentKeymaps))
        }
        // Save
        UserDefaults.standard.set(recentKeymaps, forKey: recentKeymapsKey)
    }
    
    func clearRecentKeymaps() {
        recentKeymaps = []
        UserDefaults.standard.removeObject(forKey: recentKeymapsKey)
    }
    
    func checkForUpdates() {
        isCheckingUpdate = true
        updateAvailable = nil
        isUpToDate = false
        
        let url = URL(string: "https://api.github.com/repos/\(githubRepo)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isCheckingUpdate = false
                
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tagName = json["tag_name"] as? String else {
                    return
                }
                
                let latestVersion = tagName.replacingOccurrences(of: "v", with: "")
                if latestVersion.compare(appVersion, options: .numeric) == .orderedDescending {
                    self?.updateAvailable = latestVersion
                } else {
                    self?.isUpToDate = true
                    // Auto-hide "Up to date" after 3 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        self?.isUpToDate = false
                    }
                }
            }
        }.resume()
    }
    
    func openReleasePage() {
        if let url = URL(string: "https://github.com/\(githubRepo)/releases/latest") {
            NSWorkspace.shared.open(url)
        }
    }
    
    @Published var isDownloadingUpdate = false
    @Published var downloadProgress: Double = 0
    
    func downloadUpdate() {
        guard let version = updateAvailable else { return }
        
        let dmgName = "ZMK-Keymap-Viewer-v\(version).dmg"
        let downloadURL = URL(string: "https://github.com/\(githubRepo)/releases/download/v\(version)/\(dmgName)")!
        
        isDownloadingUpdate = true
        downloadProgress = 0
        
        let task = URLSession.shared.downloadTask(with: downloadURL) { [weak self] tempURL, response, error in
            DispatchQueue.main.async {
                self?.isDownloadingUpdate = false
                
                guard let tempURL = tempURL, error == nil else {
                    // Fallback to opening release page if download fails
                    self?.openReleasePage()
                    return
                }
                
                // Move to Downloads folder
                let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
                let destinationURL = downloads.appendingPathComponent(dmgName)
                
                try? FileManager.default.removeItem(at: destinationURL) // Remove if exists
                
                do {
                    try FileManager.default.moveItem(at: tempURL, to: destinationURL)
                    // Open the DMG and quit the app so it can be replaced
                    NSWorkspace.shared.open(destinationURL)
                    // Give a moment for the DMG to mount, then quit
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        NSApplication.shared.terminate(nil)
                    }
                } catch {
                    self?.openReleasePage()
                }
            }
        }
        task.resume()
    }
}
