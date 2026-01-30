import SwiftUI

// MARK: - VisualEffectView for background blur
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Keymap Grid View Component

struct KeyboardGridView: View {
    let layer: KeymapLayer
    let layout: KeyboardLayout
    
    private var keyWidth: CGFloat {
        layout.keysPerRow.first.map { $0 > 10 ? 48 : 54 } ?? 54
    }
    private let keyHeight: CGFloat = 44
    private let keySpacing: CGFloat = 3
    private let splitGap: CGFloat = 30
    
    var body: some View {
        VStack(alignment: .center, spacing: keySpacing) {
            ForEach(0..<layout.rowCount, id: \.self) { rowIndex in
                rowView(for: rowIndex)
            }
        }
    }
    
    private func rowView(for rowIndex: Int) -> some View {
        let keysInRow = layout.keysPerRow[safe: rowIndex] ?? 0
        let maxKeysInRow = layout.keysPerRow.max() ?? 0
        let bindings = getBindingsForRow(rowIndex)
        let isThumbRow = rowIndex == layout.rowCount - 1 && layout.hasThumbCluster
        let halfCount = keysInRow / 2
        
        // For thumb row: add external padding. For other rows: increase gap
        let keysDifference = maxKeysInRow - keysInRow
        let extraGap = isThumbRow ? 0 : CGFloat(keysDifference) * (keyWidth + keySpacing)
        let externalPadding = isThumbRow ? CGFloat(keysDifference / 2) * (keyWidth + keySpacing) : 0
        let totalGap = isThumbRow ? splitGap + 20 : splitGap
        let adjustedGap = totalGap + extraGap
        
        let rowContent = HStack(spacing: keySpacing) {
            // Left half
            HStack(spacing: keySpacing) {
                ForEach(0..<halfCount, id: \.self) { colIndex in
                    if let binding = bindings[safe: colIndex] {
                        KeyView(binding: binding, isThumbKey: isThumbRow)
                            .frame(width: keyWidth, height: keyHeight)
                    }
                }
            }
            
            // Gap between halves - wider for non-thumb rows with fewer keys
            Spacer()
                .frame(width: adjustedGap)
            
            // Right half
            HStack(spacing: keySpacing) {
                ForEach(halfCount..<keysInRow, id: \.self) { colIndex in
                    if let binding = bindings[safe: colIndex] {
                        KeyView(binding: binding, isThumbKey: isThumbRow)
                            .frame(width: keyWidth, height: keyHeight)
                    }
                }
            }
        }
        
        // Add external padding for thumb row if needed
        if externalPadding > 0 {
            return AnyView(
                HStack(spacing: 0) {
                    Spacer()
                        .frame(width: externalPadding)
                    rowContent
                    Spacer()
                        .frame(width: externalPadding)
                }
                .padding(.top, isThumbRow ? 8 : 0)
            )
        } else {
            return AnyView(
                rowContent
                    .padding(.top, isThumbRow ? 8 : 0)
            )
        }
    }
    
    private func getBindingsForRow(_ row: Int) -> [KeyBinding] {
        return layer.bindings.filter { $0.row == row }.sorted { $0.column < $1.column }
    }
}

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var viewModel: KeymapViewModel
    @State private var selectedLayerIndex: Int = 0
    @State private var pathText: String = ""
    @State private var isRecordingShortcut = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with file info and layout
            headerView
            
            Divider()
            
            ZStack {
                if appState.isSettingsVisible {
                    settingsView
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else if viewModel.keymap != nil {
                    if appState.isHUDModeEnabled {
                        hudActiveView
                    } else {
                        // All normal UI
                        VStack(spacing: 0) {
                            layerTabsView
                            keymapVisualizationView
                        }
                    }
                } else {
                    emptyStateView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: appState.isSettingsVisible)
            
            Divider()
            
            // Footer with update, HUD toggle and settings buttons
            HStack(spacing: 12) {
                if let newVersion = appState.updateAvailable {
                    Button("Update (v\(newVersion))") {
                        appState.openReleasePage()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else {
                    Button(action: { appState.checkForUpdates() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .disabled(appState.isCheckingUpdate)
                    .help("Check for Updates")
                }
                
                Text("v\(appVersion)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: { appState.toggleHUD() }) {
                    Label("HUD Mode", systemImage: "window.shade.closed")
                        .foregroundColor(appState.isHUDModeEnabled ? .accentColor : .primary)
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .help("Toggle HUD Mode (\(shortcutString))")
                
                Button(action: { appState.isSettingsVisible.toggle() }) {
                    Image(systemName: "gearshape.fill")
                        .foregroundColor(appState.isSettingsVisible ? .accentColor : .primary)
                }
                .buttonStyle(.borderless)
                .help("Settings")

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            .padding(10)
        }
        .frame(minWidth: viewModel.keymap != nil ? calculateOptimalWidth(for: viewModel.keymap!.layout) : 700)
        .frame(minHeight: appState.isHUDModeEnabled ? 240 : (viewModel.keymap != nil ? calculateOptimalHeight(for: viewModel.keymap!.layout) : 500))
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            print("[ContentView] onAppear triggered")
            // Auto-load most recent keymap
            if let mostRecent = appState.recentKeymaps.first {
                print("[ContentView] Loading most recent keymap: \(mostRecent)")
                pathText = mostRecent
                loadKeymap(from: mostRecent)
            } else {
                print("[ContentView] No recent keymaps found")
            }
        }
    }
    
    private func calculateScale(for layout: KeyboardLayout) -> CGFloat {
        return 1.0 // On ne scale plus car la fenêtre s'adapte
    }

    private func calculateOptimalWidth(for layout: KeyboardLayout) -> CGFloat {
        let maxKeysInRow = CGFloat(layout.keysPerRow.max() ?? 10)
        let keyWidth: CGFloat = layout.keysPerRow.first.map { $0 > 10 ? 48 : 54 } ?? 54
        let keySpacing: CGFloat = 3
        let splitGap: CGFloat = 30
        
        let totalWidth = (maxKeysInRow * keyWidth) + ((maxKeysInRow - 2) * keySpacing) + splitGap + 60
        return max(700, totalWidth)
    }

    private func calculateOptimalHeight(for layout: KeyboardLayout) -> CGFloat {
        let rowCount = CGFloat(layout.rowCount)
        let keyHeight: CGFloat = 44
        let keySpacing: CGFloat = 3
        let thumbExtra: CGFloat = layout.hasThumbCluster ? 20 : 0
        
        // Header (~100) + Tabs (~40) + Keyboard + Footer (~40)
        let totalHeight = 100 + 40 + (rowCount * keyHeight) + ((rowCount - 1) * keySpacing) + thumbExtra + 60
        return max(500, totalHeight)
    }
    
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 4) { // Réduction du spacing interne
            HStack {
                Text("Keymap File")
                    .font(.subheadline.bold()) // Un peu plus petit pour gagner de la place
                
                Spacer()
                // Recent keymaps menu
                if !appState.recentKeymaps.isEmpty {
                    Menu {
                        ForEach(appState.recentKeymaps, id: \.self) { path in
                            Button {
                                pathText = path
                                loadKeymap(from: path)
                            } label: {
                                let filename = URL(fileURLWithPath: path).lastPathComponent
                                let isSelected = path == viewModel.currentFilePath
                                if isSelected {
                                    Label(filename, systemImage: "checkmark")
                                } else {
                                    Text(filename)
                                }
                            }
                        }
                        
                        Divider()
                        
                        Button("Clear History", role: .destructive) {
                            appState.clearRecentKeymaps()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.arrow.circlepath")
                            Text("Recent")
                                .font(.caption)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(4)
                    }
                    .menuStyle(.borderlessButton)
                }
            }
            
            // Persistent path text field
            HStack(spacing: 8) {
                TextField("Path to .keymap file", text: $pathText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .onSubmit {
                        loadFromPathText()
                    }
                
                Button("Load") {
                    loadFromPathText()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(pathText.isEmpty)
            }
            
            // Status row
            HStack(spacing: 8) {
                if let filePath = viewModel.currentFilePath {
                    Button("Open in Editor") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: filePath))
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
                
                Spacer()
                
                if let keymap = viewModel.keymap {
                    Text(keymap.layout.name)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(4)
                }
            }
        }
        .padding()
    }
    
    private var layerTabsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let keymap = viewModel.keymap {
                    ForEach(Array(keymap.layers.enumerated()), id: \.1.id) { index, layer in
                        Button(action: { selectedLayerIndex = index }) {
                            Text(layer.name)
                                .font(.system(size: 12, weight: selectedLayerIndex == index ? .semibold : .regular))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(selectedLayerIndex == index ? Color.accentColor : Color.clear)
                                )
                                .foregroundColor(selectedLayerIndex == index ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var keymapVisualizationView: some View {
        Group {
            if let keymap = viewModel.keymap,
               selectedLayerIndex < keymap.layers.count {
                let layer = keymap.layers[selectedLayerIndex]
                let layout = keymap.layout
                
                DynamicKeyboardView(
                    layer: layer,
                    layout: layout
                )
                .padding(.vertical, 20)
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "keyboard")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No keymap loaded")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("Paste a path above and press Load")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func loadFromPathText() {
        let path = pathText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return }
        guard path.hasSuffix(".keymap") else { return }
        guard FileManager.default.fileExists(atPath: path) else { return }
        loadKeymap(from: path)
        // Keep menu bar window active after loading
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Subviews

    private var settingsView: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Settings")
                    .font(.headline.bold())
                Spacer()
                Button(action: { appState.isSettingsVisible = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 5)
            .padding(.bottom, 2)
            
            VStack(alignment: .leading, spacing: 15) {
                // Global Shortcut Section
                VStack(alignment: .leading, spacing: 6) {
                    Label("Global Shortcut", systemImage: "keyboard")
                        .font(.caption.bold())
                    
                    HStack {
                        Text(shortcutString)
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(isRecordingShortcut ? Color.accentColor : Color.clear, lineWidth: 2)
                            )
                        
                        Button(isRecordingShortcut ? "Cancel" : "Record") {
                            isRecordingShortcut.toggle()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        if isRecordingShortcut {
                            ShortcutRecorder(isRecording: $isRecordingShortcut) { keyCode, modifiers in
                                var carbonMods: Int = 0
                                if modifiers.contains(.command) { carbonMods |= 256 }
                                if modifiers.contains(.shift) { carbonMods |= 512 }
                                if modifiers.contains(.option) { carbonMods |= 2048 }
                                if modifiers.contains(.control) { carbonMods |= 4096 }
                                
                                appState.updateShortcut(keyCode: Int(keyCode), modifiers: carbonMods)
                                isRecordingShortcut = false
                            }
                            .frame(width: 1, height: 1)
                            .opacity(0)
                        }
                    }
                    Text("This shortcut toggles the HUD visibility from anywhere.")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                
                Divider()
                
                // HUD Appearance
                VStack(alignment: .leading, spacing: 10) {
                    Label("HUD Appearance", systemImage: "eye")
                        .font(.caption.bold())
                    
                    HStack(spacing: 15) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text("Opacity")
                                    .font(.caption2)
                                Spacer()
                                Text("\(Int(appState.hudOpacity * 100))%")
                                    .font(.caption2.monospacedDigit())
                            }
                            Slider(value: $appState.hudOpacity, in: 0.1...1.0)
                                .controlSize(.small)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text("Auto-hide")
                                    .font(.caption2)
                                Spacer()
                                Text(appState.hudTimeout == 0 ? "Off" : String(format: "%.1fs", appState.hudTimeout))
                                    .font(.caption2.monospacedDigit())
                            }
                            Slider(value: $appState.hudTimeout, in: 0...10, step: 0.5)
                                .controlSize(.small)
                        }
                    }
                    
                    Toggle("Use Background Blur (Material)", isOn: $appState.hudUseMaterial)
                        .font(.caption2)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var hudActiveView: some View {
        VStack(spacing: 16) {
            Image(systemName: "window.shade.closed")
                .font(.system(size: 40))
                .foregroundColor(.accentColor)
            Text("HUD Mode Active")
                .font(.headline)
            Text("Press \(shortcutString) to toggle")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Button("Disable HUD Mode") {
                appState.isHUDModeEnabled = false
            }
            .buttonStyle(.bordered)
            .padding(.top, 10)
        }
    }

    private var shortcutString: String {
        // Simple mapping of common Carbon modifiers
        var items: [String] = []
        if (appState.shortcutModifiers & 256) != 0 { items.append("⌘") }
        if (appState.shortcutModifiers & 512) != 0 { items.append("⇧") }
        if (appState.shortcutModifiers & 2048) != 0 { items.append("⌥") }
        if (appState.shortcutModifiers & 4096) != 0 { items.append("⌃") }
        
        let keyName = getKeyName(UInt16(appState.shortcutKeyCode))
        items.append(keyName)
        
        return items.joined(separator: " + ")
    }
    
    private func getKeyName(_ keyCode: UInt16) -> String {
        // Basic mapping for common keys on QWERTY
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "O"
        case 32: return "U"
        case 33: return "["
        case 34: return "I"
        case 35: return "P"
        case 37: return "L"
        case 38: return "J"
        case 39: return "'"
        case 40: return "K"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        case 49: return "Space"
        case 50: return "`"
        case 51: return "Delete"
        case 53: return "Esc"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 36: return "Return"
        case 48: return "Tab"
        default:
            return "#\(keyCode)"
        }
    }
    
    private func loadKeymap(from path: String) {
        pathText = path
        viewModel.loadKeymap(from: path)
        appState.addRecentKeymap(path)
        selectedLayerIndex = 0
        // Keep menu bar window active
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}



// MARK: - Dynamic Keyboard View

struct DynamicKeyboardView: View {
    let layer: KeymapLayer
    let layout: KeyboardLayout
    
    // Key sizing - dynamically sized based on layout
    private var keyWidth: CGFloat {
        // Smaller keys for layouts with more keys per row
        layout.keysPerRow.first.map { $0 > 10 ? 48 : 54 } ?? 54
    }
    private let keyHeight: CGFloat = 44
    private let keySpacing: CGFloat = 3
    private let splitGap: CGFloat = 30  // Gap between left and right halves
    
    var body: some View {
        VStack(alignment: .center, spacing: keySpacing) {
            ForEach(0..<layout.rowCount, id: \.self) { rowIndex in
                rowView(for: rowIndex)
            }
        }
    }
    
    private func rowView(for rowIndex: Int) -> some View {
        let keysInRow = layout.keysPerRow[safe: rowIndex] ?? 0
        let halfCount = keysInRow / 2
        let bindings = getBindingsForRow(rowIndex)
        
        let isThumbRow = rowIndex == layout.rowCount - 1 && layout.hasThumbCluster
        
        return HStack(spacing: keySpacing) {
            // Left half
            HStack(spacing: keySpacing) {
                ForEach(0..<halfCount, id: \.self) { colIndex in
                    if let binding = bindings[safe: colIndex] {
                        KeyView(binding: binding, isThumbKey: isThumbRow)
                            .frame(width: keyWidth, height: keyHeight)
                    }
                }
            }
            
            // Gap between halves
            Spacer()
                .frame(width: isThumbRow ? splitGap + 20 : splitGap)
            
            // Right half
            HStack(spacing: keySpacing) {
                ForEach(halfCount..<keysInRow, id: \.self) { colIndex in
                    if let binding = bindings[safe: colIndex] {
                        KeyView(binding: binding, isThumbKey: isThumbRow)
                            .frame(width: keyWidth, height: keyHeight)
                    }
                }
            }
        }
        .padding(.top, isThumbRow ? 8 : 0)  // Extra space before thumb row
    }
    
    private func getBindingsForRow(_ row: Int) -> [KeyBinding] {
        return layer.bindings.filter { $0.row == row }.sorted { $0.column < $1.column }
    }
}

// MARK: - Key View with Tooltip

struct KeyView: View {
    let binding: KeyBinding
    let isThumbKey: Bool
    
    @State private var isHovered = false
    @State private var showTooltip = false
    
    var body: some View {
        ZStack {
            // Key background
            RoundedRectangle(cornerRadius: 10)
                .fill(keyBackgroundColor)
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            
            // Key border
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isHovered ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: isHovered ? 2 : 1)
            
            // Key label
            Text(binding.displayText)
                .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                .foregroundColor(textColor)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .padding(4)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
            if hovering {
                // Show tooltip after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if isHovered {
                        showTooltip = true
                    }
                }
            } else {
                showTooltip = false
            }
        }
        .overlay(alignment: .top) {
            if showTooltip {
                TooltipView(text: binding.rawCode)
                    .offset(y: -35)
                    .zIndex(100)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: showTooltip)
    }
    
    private var keyBackgroundColor: Color {
        if binding.displayText == "▽" {
            return Color.gray.opacity(0.1)
        } else if binding.displayText == "✕" {
            return Color.red.opacity(0.1)
        } else if isThumbKey {
            return Color.blue.opacity(0.15)
        } else if binding.displayText.contains("\n") {
            // Mod-tap or layer-tap
            return Color.purple.opacity(0.15)
        } else if binding.rawCode.hasPrefix("&mo") || binding.rawCode.hasPrefix("&to") || binding.rawCode.hasPrefix("&tog") {
            // Layer toggle/momentary - check raw code, not display text
            return Color.orange.opacity(0.15)
        } else if ["BT", "RESET", "BOOT", "STUDIO"].contains(where: { binding.displayText.contains($0) }) {
            return Color.green.opacity(0.15)
        }
        return Color(NSColor.controlBackgroundColor)
    }
    
    private var textColor: Color {
        if binding.displayText == "▽" {
            return .secondary
        }
        return .primary
    }
    
    private var fontSize: CGFloat {
        if binding.displayText.count > 4 {
            return 9
        } else if binding.displayText.count > 2 {
            return 11
        }
        return 12
    }
}

// MARK: - Tooltip View

struct TooltipView: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black.opacity(0.85))
            )
            .fixedSize()
    }
}

// MARK: - Array Extension for Safe Access

extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Array Safe Subscript Extension

extension Collection {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Shortcut Recorder helper
struct ShortcutRecorder: NSViewRepresentable {
    @Binding var isRecording: Bool
    var onRecord: (UInt16, NSEvent.ModifierFlags) -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = ShortcutRecordingView()
        view.onRecord = { keyCode, modifiers in
            onRecord(keyCode, modifiers)
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if isRecording {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

class ShortcutRecordingView: NSView {
    var onRecord: ((UInt16, NSEvent.ModifierFlags) -> Void)?
    
    override var acceptsFirstResponder: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape to cancel
            return
        }
        onRecord?(event.keyCode, event.modifierFlags)
    }
}

// MARK: - Preview

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}