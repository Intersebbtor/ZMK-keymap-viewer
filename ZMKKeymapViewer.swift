import SwiftUI
import AppKit

let appVersion = "1.1.0"
let githubRepo = "Intersebbtor/ZMK-keymap-viewer"

@main
struct ZMKKeymapViewerApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var keymapViewModel = KeymapViewModel()
    
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
                .environmentObject(keymapViewModel)
                .onAppear {
                    appState.keymapViewModel = keymapViewModel
                    appState.setupHUDPanel(with: keymapViewModel)
                }
        } label: {
            Image(systemName: "keyboard")
        }
        .menuBarExtraStyle(.window)
    }
}

class AppState: ObservableObject {
    // Keep a static reference for global shortcut only
    private static var instance: AppState?
    
    @Published var recentKeymaps: [String] = []
    @Published var updateAvailable: String? = nil
    @Published var isCheckingUpdate = false
    
    // HUD Settings
    @AppStorage("isHUDModeEnabled") var isHUDModeEnabled = false
    @AppStorage("hudOpacity") var hudOpacity: Double = 0.9
    @AppStorage("hudUseMaterial") var hudUseMaterial = true
    @AppStorage("hudTimeout") var hudTimeout: Double = 3.0
    
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
    
    var keymapViewModel: KeymapViewModel?
    
    init() {
        AppState.instance = self
        loadRecentKeymaps()
        setupActivityMonitor()
        setupGlobalShortcut()
        
        // Deferred initialization of the HUD to avoid blocking startup
        // The keymapViewModel will be assigned from ZMKKeymapViewerApp
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
    
    func updateShortcut(keyCode: Int, modifiers: Int) {
        shortcutKeyCode = keyCode
        shortcutModifiers = modifiers
        setupGlobalShortcut()
    }
    
    func setupActivityMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged, .mouseMoved, .leftMouseDown]) { [weak self] event in
            guard let self = self else { return }
            
            if event.type == .mouseMoved {
                // For mouse movements, we only wake up the HUD if hovering over it
                if let panel = self.floatingPanel, 
                   panel.isVisible,
                   panel.frame.contains(NSEvent.mouseLocation) {
                    self.resetInactivity()
                }
            } else {
                // For other events (keystrokes), always wake up
                self.resetInactivity()
            }
        }
        
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .mouseMoved, .leftMouseDown]) { [weak self] event in
            guard let self = self else { return event }
            
            if event.type == .mouseMoved {
                // Same logic for local events
                if let panel = self.floatingPanel, 
                   panel.isVisible,
                   panel.frame.contains(NSEvent.mouseLocation) {
                    self.resetInactivity()
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
    
    func resetInactivity() {
        DispatchQueue.main.async {
            self.isHUDInactive = false
            self.activityTimer?.invalidate()
            
            guard self.hudTimeout > 0 else { return }
            
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
            if let keymapVM = keymapViewModel {
                setupHUDPanel(with: keymapVM)
                if let panel = floatingPanel {
                    panel.makeKeyAndOrderFront(nil)
                    isHUDModeEnabled = true
                }
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
                }
            }
        }.resume()
    }
    
    func openReleasePage() {
        if let url = URL(string: "https://github.com/\(githubRepo)/releases/latest") {
            NSWorkspace.shared.open(url)
        }
    }
}
