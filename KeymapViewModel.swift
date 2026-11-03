import Foundation
import Combine

class KeymapViewModel: ObservableObject {
    @Published var keymap: Keymap?
    @Published var currentFilePath: String?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    /// Displayed and live layer, shared by the menu and the HUD
    @Published private(set) var layerSelection = LayerSelection()

    var displayedLayerIndex: Int { layerSelection.displayedIndex }

    /// Key positions currently held on the keyboard
    @Published private(set) var pressedPositions: Set<Int> = []

    /// Name of the keyboard's active layer, or "Layer N" if the keymap file does not have it
    var liveLayerName: String? {
        guard let index = layerSelection.liveIndex else { return nil }
        return keymap?.layers[safe: index]?.name ?? "Layer \(index)"
    }

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
                
                if let parsed = KeymapParser.parse(from: data, filePath: filePath) {
                    DispatchQueue.main.async {
                        // A reload of the same file keeps the selected layer
                        if filePath == self.currentFilePath {
                            self.layerSelection.clamp(layerCount: parsed.layers.count)
                        } else {
                            self.layerSelection.reset(layerCount: parsed.layers.count)
                        }
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
    
    // MARK: - Layer selection

    func selectLayer(_ index: Int) {
        layerSelection.selectManually(index)
    }

    func applyLiveLayer(_ index: Int, follow: Bool) {
        layerSelection.applyLive(index, layerCount: keymap?.layers.count ?? 0, follow: follow)
    }

    func clearLiveLayer() {
        layerSelection.clearLive()
        // Releases sent while disconnected never arrive
        pressedPositions = []
    }

    func setKey(position: Int, pressed: Bool) {
        if pressed {
            pressedPositions.insert(position)
        } else {
            pressedPositions.remove(position)
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