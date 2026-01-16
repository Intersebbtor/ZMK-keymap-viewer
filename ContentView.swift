import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = KeymapViewModel()
    @State private var selectedLayerIndex: Int = 0
    @State private var pathText: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with file info and layout
            headerView
            
            Divider()
            
            if viewModel.keymap != nil {
                // Layer tabs
                layerTabsView
                
                // Keymap visualization
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    keymapVisualizationView
                        .padding()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                emptyStateView
            }
            
            Divider()
            
            // Footer with quit button
            HStack {
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            .padding(8)
        }
        .frame(minWidth: 750, minHeight: 450)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            // Auto-load most recent keymap
            if let mostRecent = appState.recentKeymaps.first {
                pathText = mostRecent
                loadKeymap(from: mostRecent)
            }
        }
    }
    
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Keymap File")
                    .font(.headline)
                
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
                TextField("Paste or type path to .keymap file", text: $pathText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .onSubmit {
                        loadFromPathText()
                    }
                
                Button("Load") {
                    loadFromPathText()
                }
                .buttonStyle(.borderedProminent)
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
    }
    
    private func loadKeymap(from path: String) {
        pathText = path
        viewModel.loadKeymap(from: path)
        appState.addRecentKeymap(path)
        selectedLayerIndex = 0
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
            RoundedRectangle(cornerRadius: 6)
                .fill(keyBackgroundColor)
                .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
            
            // Key border
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isHovered ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: isHovered ? 2 : 1)
            
            // Key label
            Text(binding.displayText)
                .font(.system(size: fontSize, weight: .medium, design: .rounded))
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

// MARK: - Preview

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}