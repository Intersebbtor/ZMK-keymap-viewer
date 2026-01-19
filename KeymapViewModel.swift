import Foundation
import Combine

class KeymapViewModel: ObservableObject {
    @Published var keymap: Keymap?
    @Published var currentFilePath: String?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    private var fileMonitor: FileMonitor?
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Don't auto-load here - ContentView.onAppear handles loading
        // This prevents double-loading and race conditions
    }
    
    func loadKeymap(from filePath: String) {
        // Validate path before attempting load
        guard !filePath.isEmpty else {
            print("[KeymapVM] Empty file path, skipping load")
            return
        }
        
        guard FileManager.default.fileExists(atPath: filePath) else {
            print("[KeymapVM] File does not exist: \(filePath)")
            DispatchQueue.main.async {
                self.errorMessage = "File not found"
            }
            return
        }
        
        print("[KeymapVM] Loading keymap from: \(filePath)")
        isLoading = true
        errorMessage = nil
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                let data = try String(contentsOfFile: filePath, encoding: .utf8)
                
                if let parsed = KeymapParser.parse(from: data) {
                    DispatchQueue.main.async {
                        self.keymap = parsed
                        self.currentFilePath = filePath
                        self.isLoading = false
                        
                        // Save to UserDefaults
                        UserDefaults.standard.set(filePath, forKey: "lastKeymapPath")
                        
                        // Setup file monitoring
                        self.setupFileMonitoring(for: filePath)
                        
                        print("[KeymapVM] Successfully loaded: \(parsed.layout.name) with \(parsed.layers.count) layers")
                    }
                } else {
                    print("[KeymapVM] Failed to parse keymap file")
                    DispatchQueue.main.async {
                        self.errorMessage = "Failed to parse keymap file"
                        self.isLoading = false
                    }
                }
            } catch {
                print("[KeymapVM] Error reading file: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.errorMessage = "Error reading file: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    func reloadCurrentKeymap() {
        if let path = currentFilePath {
            loadKeymap(from: path)
        }
    }
    
    private func setupFileMonitoring(for filePath: String) {
        // Cancel existing monitor
        fileMonitor?.stopMonitoring()
        
        // Create new monitor
        fileMonitor = FileMonitor(filePath: filePath)
        fileMonitor?.onFileChange = { [weak self] in
            print("File changed, reloading...")
            self?.reloadCurrentKeymap()
        }
        fileMonitor?.startMonitoring()
    }
    
    deinit {
        fileMonitor?.stopMonitoring()
    }
}