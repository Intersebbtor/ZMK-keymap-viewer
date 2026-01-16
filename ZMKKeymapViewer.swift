import SwiftUI

@main
struct ZMKKeymapViewerApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(appState)
        } label: {
            Image(systemName: "keyboard")
        }
        .menuBarExtraStyle(.window)
    }
}

class AppState: ObservableObject {
    @Published var recentKeymaps: [String] = []
    
    private let recentKeymapsKey = "recentKeymaps"
    private let maxRecentKeymaps = 5
    
    init() {
        loadRecentKeymaps()
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
}