import SwiftUI

let appVersion = "1.0.3"
let githubRepo = "Intersebbtor/ZMK-keymap-viewer"

@main
struct ZMKKeymapViewerApp: App {
    @StateObject private var appState = AppState()
    
    init() {
        print("[App] ZMKKeymapViewer starting...")
        
        // Set up global exception handler for debugging
        NSSetUncaughtExceptionHandler { exception in
            print("[App] CRASH: \\(exception)")
            print("[App] Reason: \\(exception.reason ?? \"unknown\")")
            print("[App] Stack: \\(exception.callStackSymbols.joined(separator: \"\\n\"))")
        }
    }
    
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
    @Published var updateAvailable: String? = nil
    @Published var isCheckingUpdate = false
    
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