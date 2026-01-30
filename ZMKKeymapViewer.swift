import SwiftUI
import AppKit

let appVersion = "1.0.4"
let githubRepo = "Intersebbtor/ZMK-keymap-viewer"

@main
struct ZMKKeymapViewerApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var keymapViewModel = KeymapViewModel()
    
    init() {
        print("[App] ZMKKeymapViewer starting...")
        
        // Set up global exception handler for debugging
        NSSetUncaughtExceptionHandler { exception in
            print("[App] CRASH: \(exception)")
            print("[App] Reason: \(exception.reason ?? "unknown")")
            print("[App] Stack: \(exception.callStackSymbols.joined(separator: "\n"))")
        }
    }
    
    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(appState)
                .environmentObject(keymapViewModel)
                .onAppear {
                    appState.setupFloatingPanel(with: AnyView(HUDView().environmentObject(appState).environmentObject(keymapViewModel)))
                }
        } label: {
            Image(systemName: "keyboard")
        }
        .menuBarExtraStyle(.window)
    }
}

class AppState: ObservableObject {
    @Published var recentKeymaps: [String] = []
    @Published var updateAvailable: String? = nil
    @Published var isCheckingUpdate = false
    
    // HUD Settings
    @AppStorage("isHUDModeEnabled") var isHUDModeEnabled = false
    @AppStorage("hudOpacity") var hudOpacity: Double = 0.9
    @AppStorage("hudUseMaterial") var hudUseMaterial = true
    @AppStorage("hudTimeout") var hudTimeout: Double = 3.0
    
    @Published var isHUDInactive = false
    private var activityTimer: Timer?
    private var eventMonitor: Any?
    
    private let recentKeymapsKey = "recentKeymaps"
    private let maxRecentKeymaps = 5
    
    var floatingPanel: FloatingPanel?
    
    init() {
        loadRecentKeymaps()
        setupActivityMonitor()
    }
    
    func setupActivityMonitor() {
        // Monitor global events
        // Note: Global .keyDown monitoring requires Accessibility permissions in System Settings
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged, .mouseMoved, .leftMouseDown]) { [weak self] _ in
            self?.resetInactivity()
        }
        
        // Also monitor local events (when the app has focus)
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .mouseMoved, .leftMouseDown]) { [weak self] event in
            self?.resetInactivity()
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
                panel.orderOut(nil)
                isHUDModeEnabled = false
            } else {
                panel.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                isHUDModeEnabled = true
            }
        }
    }
    
    func setupFloatingPanel(with view: AnyView) {
        if floatingPanel == nil {
            let panel = FloatingPanel(
                view: view,
                contentRect: NSRect(x: 100, y: 100, width: 700, height: 400)
            )
            panel.center()
            floatingPanel = panel
            
            // Auto-show if was enabled in previous session
            if isHUDModeEnabled {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    panel.makeKeyAndOrderFront(nil)
                }
            }
        }
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
