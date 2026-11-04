import Foundation
import Combine

class KeymapViewModel: ObservableObject {
    /// The displayed keymap: read from the keyboard when available, else the file
    @Published private(set) var keymap: Keymap?
    @Published var currentFilePath: String?
    /// Name of the keyboard the displayed keymap was read from, nil when it comes from the file
    @Published private(set) var keyboardKeymapName: String?
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

    /// Names given to keys with a right-click, by what the key does (its
    /// label), so a name applies wherever the same binding sits
    @Published private(set) var keyNames: [String: String] = UserDefaults.standard.dictionary(forKey: KeymapViewModel.keyNamesKey) as? [String: String] ?? [:]
    private static let keyNamesKey = "keyNames"

    private var fileKeymap: Keymap?
    private var keyboardSnapshot: StudioSnapshot?

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
                        let isNewFile = filePath != self.currentFilePath
                        self.fileKeymap = parsed
                        self.updateDisplayedKeymap(resetSelection: isNewFile && self.keyboardSnapshot == nil)
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
    
    // MARK: - Keymap from the keyboard

    /// Shows the keymap read from the keyboard, with aliases and missing
    /// layer names from the file. nil goes back to the file.
    func applyKeyboardSnapshot(_ snapshot: StudioSnapshot?) {
        let switchesSource = (snapshot == nil) != (keyboardSnapshot == nil)
        keyboardSnapshot = snapshot
        updateDisplayedKeymap(resetSelection: switchesSource)
    }

    private func updateDisplayedKeymap(resetSelection: Bool) {
        var shown = fileKeymap
        var keyboardName: String?
        if let snapshot = keyboardSnapshot,
           let fromKeyboard = StudioKeymapConverter.keymap(
               from: snapshot,
               aliases: aliases(matching: snapshot),
               fallbackLayerNames: fileKeymap?.layers.map(\.name) ?? []
           ) {
            shown = fromKeyboard
            keyboardName = snapshot.deviceName
        }

        if var named = shown, !keyNames.isEmpty {
            named.layers = named.layers.map(applyingKeyNames)
            shown = named
        }

        let layerCount = shown?.layers.count ?? 0
        if resetSelection {
            layerSelection.reset(layerCount: layerCount)
        } else {
            layerSelection.clamp(layerCount: layerCount)
        }
        keymap = shown
        keyboardKeymapName = keyboardName
    }

    // MARK: - Key names

    func keyName(for binding: KeyBinding) -> String? {
        keyNames[binding.displayText]
    }

    /// An empty name removes it
    func setKeyName(_ name: String?, for binding: KeyBinding) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        keyNames[binding.displayText] = trimmed.isEmpty ? nil : trimmed
        UserDefaults.standard.set(keyNames, forKey: Self.keyNamesKey)
        updateDisplayedKeymap(resetSelection: false)
    }

    /// A name given in the app wins over an alias comment in the file
    private func applyingKeyNames(_ layer: KeymapLayer) -> KeymapLayer {
        KeymapLayer(
            name: layer.name,
            bindings: layer.bindings.map { binding in
                guard let name = keyNames[binding.displayText] else { return binding }
                return KeyBinding(displayText: binding.displayText, rawCode: binding.rawCode, alias: name, row: binding.row, column: binding.column)
            },
            rowCount: layer.rowCount,
            columnCount: layer.columnCount
        )
    }

    /// Labels again after the keyboard layout changed (KeyCharacters)
    func refreshLabels() {
        updateDisplayedKeymap(resetSelection: false)
        reloadCurrentKeymap()
    }

    /// Aliases of the file's layers whose key count matches the keyboard's
    private func aliases(matching snapshot: StudioSnapshot) -> [[String?]] {
        guard let file = fileKeymap else { return [] }
        return snapshot.layers.indices.map { index in
            guard let layer = file.layers[safe: index], layer.bindings.count == snapshot.layers[index].bindings.count else {
                return []
            }
            return layer.bindings.map(\.alias)
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