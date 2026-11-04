import SwiftUI
import UniformTypeIdentifiers

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
    /// Key positions currently held on the keyboard (live layer feature)
    var pressedPositions: Set<Int> = []

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
        
        // Calculate adjustments based on row type
        let keysDifference = maxKeysInRow - keysInRow
        let oneKeyWidth = keyWidth + keySpacing
        
        // Only apply split-related gaps if this is a split keyboard
        let extraGap = layout.isSplit && !isThumbRow && keysInRow < maxKeysInRow ? CGFloat(keysDifference) * oneKeyWidth : 0
        let baseGap = layout.isSplit ? (isThumbRow ? splitGap + 20 : splitGap) : 0
        let adjustedGap = baseGap + extraGap
        
        // For thumb row: add symmetric external padding (only for split keyboards)
        let externalPadding = layout.isSplit && isThumbRow && keysInRow < maxKeysInRow ? CGFloat(keysDifference / 2) * oneKeyWidth : 0
        
        let rowContent: AnyView
        
        if layout.isSplit {
            // Split keyboard: render left half, gap, right half
            rowContent = AnyView(
                HStack(spacing: keySpacing) {
                    // Left half
                    HStack(spacing: keySpacing) {
                        ForEach(0..<halfCount, id: \.self) { colIndex in
                            if let binding = bindings[safe: colIndex] {
                                KeyView(binding: binding, isThumbKey: isThumbRow, isPressed: isPressed(binding))
                                    .frame(width: keyWidth, height: keyHeight)
                            }
                        }
                    }
                    
                    // Gap between halves
                    Spacer()
                        .frame(width: adjustedGap)
                    
                    // Right half
                    HStack(spacing: keySpacing) {
                        ForEach(halfCount..<keysInRow, id: \.self) { colIndex in
                            if let binding = bindings[safe: colIndex] {
                                KeyView(binding: binding, isThumbKey: isThumbRow, isPressed: isPressed(binding))
                                    .frame(width: keyWidth, height: keyHeight)
                            }
                        }
                    }
                }
            )
        } else {
            // Non-split keyboard: render all keys in a single row
            rowContent = AnyView(
                HStack(spacing: keySpacing) {
                    ForEach(0..<keysInRow, id: \.self) { colIndex in
                        if let binding = bindings[safe: colIndex] {
                            KeyView(binding: binding, isThumbKey: isThumbRow, isPressed: isPressed(binding))
                                .frame(width: keyWidth, height: keyHeight)
                        }
                    }
                }
            )
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

    private func isPressed(_ binding: KeyBinding) -> Bool {
        guard !pressedPositions.isEmpty, let position = layer.position(of: binding) else { return false }
        return pressedPositions.contains(position)
    }
}

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var viewModel: KeymapViewModel
    @State private var isRecordingShortcut = false
    @State private var isDropTargeted = false
    @State private var keyNameText = ""
    @State private var showsNameSyntax = false
    @FocusState private var isKeyNameFocused: Bool

    /// No keymap yet, or its last step: the setup guide takes the whole popover
    private var showsSetup: Bool {
        (viewModel.keymap == nil || !appState.hasSeenKeyNamesGuide) && !appState.isSettingsVisible
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with file info and layout
            if !showsSetup {
                headerView

                Divider()
            }
            
            ZStack {
                if appState.isSettingsVisible {
                    // Scrollable, so tall settings never push the header and
                    // footer out of the popover (which also broke clicks)
                    ScrollView(.vertical, showsIndicators: false) {
                        settingsView
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                } else if viewModel.keymap != nil {
                    if !appState.hasSeenKeyNamesGuide {
                        keyNamesGuideView
                    } else if appState.isHUDModeEnabled {
                        hudActiveView
                    } else {
                        // All normal UI
                        VStack(spacing: 0) {
                            layerTabsView
                            keymapVisualizationView
                        }
                        .overlay {
                            if let binding = appState.keyBeingNamed {
                                keyNameEditor(for: binding)
                            }
                        }
                    }
                } else {
                    setupView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: appState.isSettingsVisible)
            
            Divider()
            
            // Footer with update, HUD toggle and settings buttons
            HStack(spacing: 12) {
                if appState.isDownloadingUpdate {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Downloading...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else if let newVersion = appState.updateAvailable {
                    Button {
                        appState.downloadUpdate()
                    } label: {
                        Label("Download v\(newVersion)", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else if appState.isUpToDate {
                    Label("Up to date", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                } else {
                    Button(action: { appState.checkForUpdates() }) {
                        Label("Check for updates", systemImage: "arrow.clockwise")
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .disabled(appState.isCheckingUpdate)
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
                
                Divider()
                    .frame(height: 16)
                
                Button(action: { appState.isSettingsVisible.toggle() }) {
                    Label("Settings", systemImage: "gearshape.fill")
                        .foregroundColor(appState.isSettingsVisible ? .accentColor : .primary)
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .help("Settings")
                
                Divider()
                    .frame(height: 16)

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("Quit", systemImage: "xmark.circle")
                        .foregroundColor(.primary)
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
                loadKeymap(from: mostRecent)
            } else {
                print("[ContentView] No recent keymaps found")
            }
        }
        // A .keymap file dropped anywhere on the popover loads
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: loadDroppedKeymap)
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor, lineWidth: 3)
                    .padding(2)
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            if showsNameSyntax {
                nameSyntaxCard
            }
        }
        // Reopening the popover starts on the keymap, not on the settings
        .background(WindowHideObserver {
            print("[ContentView] Popover hidden")
            appState.isSettingsVisible = false
            appState.keyBeingNamed = nil
            appState.holdsShownLayer = false
            showsNameSyntax = false
        })
    }
    
    private func calculateScale(for layout: KeyboardLayout) -> CGFloat {
        return 1.0 // No more scaling because the window adapts
    }

    private func calculateOptimalWidth(for layout: KeyboardLayout) -> CGFloat {
        let maxKeysInRow = CGFloat(layout.keysPerRow.max() ?? 10)
        let keyWidth: CGFloat = layout.keysPerRow.first.map { $0 > 10 ? 48 : 54 } ?? 54
        let keySpacing: CGFloat = 3
        let splitGap: CGFloat = layout.isSplit ? 30 : 0
        let horizontalPadding: CGFloat = 40 // 20px on each side
        
        let totalWidth = (maxKeysInRow * keyWidth) + ((maxKeysInRow - 1) * keySpacing) + splitGap + horizontalPadding
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
        VStack(alignment: .leading, spacing: 4) { // Reduce internal spacing
            HStack {
                Text("Keymap File")
                    .font(.subheadline.bold()) // A bit smaller to save space

                Spacer()

                Button {
                    chooseKeymapFile()
                } label: {
                    Label("Choose File…", systemImage: "folder")
                }
                .controlSize(.small)

                // Recent keymaps menu
                if !appState.recentKeymaps.isEmpty {
                    Menu {
                        ForEach(appState.recentKeymaps, id: \.self) { path in
                            Button {
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
                        
                        Button(role: .destructive) {
                            appState.clearRecentKeymaps()
                        } label: {
                            Label("Clear History", systemImage: "trash")
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
            
            // The loaded file, ~ instead of the home folder: shorter, and
            // keeps the user name out of screenshots
            if let filePath = viewModel.currentFilePath {
                Text((filePath as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 6) {
                    Text("You may choose your keymap file if you want to set your key and macro names there.")
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Button("Show me how") { showsNameSyntax = true }
                        .buttonStyle(.link)
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // Status row
            HStack(spacing: 8) {
                keyboardSourceView

                if let filePath = viewModel.currentFilePath {
                    Button {
                        NSWorkspace.shared.open(URL(fileURLWithPath: filePath))
                    } label: {
                        Label("Open in Editor", systemImage: "pencil.and.outline")
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
    
    /// Where the shown keymap comes from when the keyboard is involved
    @ViewBuilder
    private var keyboardSourceView: some View {
        let device = appState.liveDeviceName ?? viewModel.keyboardKeymapName ?? "Keyboard"
        switch appState.keyboardKeymapStatus {
        case .loading:
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text("Reading \(device)…")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        case .locked:
            Button {
                appState.refreshKeyboardKeymap()
            } label: {
                Label("Press &studio_unlock to read \(device)", systemImage: "lock")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
            .buttonStyle(.plain)
            .help("ZMK Studio is locked. Once unlocked, the keymap loads from the keyboard. Click to check again.")
        case .failed:
            Button {
                appState.refreshKeyboardKeymap()
            } label: {
                Label("\(device) didn't send its keymap", systemImage: "exclamationmark.triangle")
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .foregroundColor(.secondary)
            .help("Retry. Reading the keymap needs ZMK Studio in the firmware.")
        case .saved:
            if let name = viewModel.keyboardKeymapName {
                Button {
                    appState.refreshKeyboardKeymap()
                } label: {
                    Label("From \(name) · saved", systemImage: "keyboard")
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .help("Read earlier from \(name). Click to read it again; when the keyboard is locked, press &studio_unlock first.")
            }
        case .idle, .loaded:
            if let name = viewModel.keyboardKeymapName {
                Button {
                    appState.refreshKeyboardKeymap()
                } label: {
                    Label("From \(name)", systemImage: "keyboard")
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .help("The keymap is read from the keyboard. Click to read it again.")
            }
        }
    }

    private var selectedLayerIndex: Int { viewModel.displayedLayerIndex }

    private var layerTabsView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 4) {
                if let keymap = viewModel.keymap {
                    let layers = Array(keymap.layers.enumerated())
                    // Split into rows of max 6 layers each
                    let maxPerRow = 6
                    let rows = stride(from: 0, to: layers.count, by: maxPerRow).map { start in
                        Array(layers[start..<min(start + maxPerRow, layers.count)])
                    }
                    ForEach(0..<rows.count, id: \.self) { rowIdx in
                        HStack(spacing: 8) {
                            ForEach(rows[rowIdx], id: \.1.id) { index, layer in
                                Button(action: { viewModel.selectLayer(index) }) {
                                    Text(layer.name)
                                        .font(.system(size: 11, weight: selectedLayerIndex == index ? .semibold : .regular))
                                        .lineLimit(1)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
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
                }
            }
            .padding(.vertical, 8)
        }
        .frame(maxHeight: 120) // Limit height, scroll if more layers
        .frame(maxWidth: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var keymapVisualizationView: some View {
        Group {
            if let keymap = viewModel.keymap,
               selectedLayerIndex < keymap.layers.count {
                let layer = keymap.layers[selectedLayerIndex]
                let layout = keymap.layout
                
                KeyboardGridView(
                    layer: layer,
                    layout: layout,
                    pressedPositions: viewModel.pressedPositions
                )
                .padding(20)
                .environment(\.keyNaming, KeyNaming(
                    name: askForKeyName,
                    hasName: { viewModel.keyName(for: $0) != nil },
                    removeName: { viewModel.setKeyName(nil, for: $0) }
                ))
            }
        }
    }
    
    // MARK: - Setup guide

    /// First start: two ways to a keymap, from the keyboard or from a file
    private var setupView: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Image(systemName: "keyboard")
                    .font(.system(size: 36))
                    .foregroundColor(.accentColor)
                Text("Show your keymap")
                    .font(.title2.bold())
                Text("Read it straight from your keyboard, or load your .keymap file.")
                    .foregroundColor(.secondary)
            }

            HStack(alignment: .top, spacing: 16) {
                setupCard(title: "From your keyboard", systemImage: "dot.radiowaves.left.and.right") {
                    keyboardSetupContent
                }
                setupCard(title: "From a file", systemImage: "doc.text") {
                    Text("Load the .keymap file from your zmk-config. The app follows it when you change it.")
                    Button {
                        chooseKeymapFile()
                    } label: {
                        Label("Choose File…", systemImage: "folder")
                    }
                    .buttonStyle(.borderedProminent)
                    Text("or drop it anywhere on this window")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func setupCard<Content: View>(title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content()
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2)))
    }

    /// Walks through connecting and unlocking; it moves on by itself
    @ViewBuilder
    private var keyboardSetupContent: some View {
        let device = appState.liveDeviceName ?? "Your keyboard"
        let firmwareGuide = URL(string: "https://github.com/\(githubRepo)#-live-layer")!
        if !appState.readKeymapFromKeyboard {
            Text("Reading the keymap from the keyboard is turned off.")
            Button("Turn On") { appState.readKeymapFromKeyboard = true }
        } else if appState.liveDeviceName == nil {
            Text("Connect your ZMK keyboard over USB or Bluetooth. Its firmware needs ZMK Studio and the layer notifier module.")
            waitingRow("Waiting for a keyboard…")
            Link("How to set up the firmware", destination: firmwareGuide)
                .font(.caption)
        } else {
            switch appState.keyboardKeymapStatus {
            case .locked:
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lock.fill")
                        .font(.title2)
                        .foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(device) is locked")
                            .bold()
                        Text("Press **&studio_unlock** on your keyboard. ZMK Studio keeps the keymap locked until then.")
                    }
                }
                waitingRow("Listening for the unlock…")
            case .failed:
                Text("\(device) didn't send its keymap. Its firmware might not have ZMK Studio.")
                Button("Try Again") { appState.refreshKeyboardKeymap() }
                Link("How to set up the firmware", destination: firmwareGuide)
                    .font(.caption)
            case .idle, .loading, .loaded, .saved:
                Text("Connected to \(device).")
                waitingRow("Reading the keymap…")
            }
        }
    }

    private func waitingRow(_ text: String) -> some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    /// Last step of the setup guide: what the labels show and how to name
    /// shortcuts and macros. The way that fits where the keymap came from
    /// comes first.
    private var keyNamesGuideView: some View {
        let fromKeyboard = viewModel.keyboardKeymapName != nil
        let rightClick = guideWay(
            systemImage: "cursorarrow.click.2",
            title: "Right-click a key",
            text: "Choose Name This Key… and type a name. It shows on every key that does the same."
        )
        let fileComment = guideWay(
            systemImage: "doc.text",
            title: "Or in your .keymap file",
            text: "Put a comment with = right after the binding:",
            code: "&kp LS(LG(N4)) /* =Screenshot */"
        )
        return VStack(spacing: 18) {
            VStack(spacing: 6) {
                Image(systemName: "character.cursor.ibeam")
                    .font(.system(size: 32))
                    .foregroundColor(.accentColor)
                Text("Name your keys")
                    .font(.title2.bold())
                Text("Keys that type a character show it, like € or ß. Shortcuts and macros show their keys, so give them a name you recognize:")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 480)
            }

            HStack(spacing: 12) {
                guideKey("⇧+⌘+4")
                Image(systemName: "arrow.right")
                    .foregroundColor(.secondary)
                guideKey("Screenshot", highlighted: true)
            }

            VStack(alignment: .leading, spacing: 12) {
                if fromKeyboard {
                    rightClick
                    fileComment
                } else {
                    fileComment.replacingTitle("In your .keymap file")
                    rightClick.replacingTitle("Or right-click a key")
                }
            }
            .frame(maxWidth: 480)

            Button("Show My Keymap") {
                appState.hasSeenKeyNamesGuide = true
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func guideKey(_ label: String, highlighted: Bool = false) -> some View {
        Text(label)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .frame(minWidth: 54, minHeight: 44)
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor)))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(highlighted ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: highlighted ? 2 : 1)
            )
    }

    private func guideWay(systemImage: String, title: String, text: String, code: String? = nil) -> GuideWay {
        GuideWay(systemImage: systemImage, title: title, text: text, code: code)
    }

    /// Naming happens inside the popover: a separate dialog would take the
    /// focus and close it
    private func askForKeyName(_ binding: KeyBinding) {
        keyNameText = viewModel.keyName(for: binding) ?? binding.alias ?? ""
        appState.keyBeingNamed = binding
        DispatchQueue.main.async {
            isKeyNameFocused = true
        }
    }

    private func keyNameEditor(for binding: KeyBinding) -> some View {
        let current = binding.displayText.replacingOccurrences(of: "\n", with: " ")
        return ZStack {
            Color.black.opacity(0.25)
                .onTapGesture { appState.keyBeingNamed = nil }

            VStack(alignment: .leading, spacing: 12) {
                Text("Name this key")
                    .font(.headline)
                Text("Shown instead of \(current) wherever that binding sits.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                TextField("e.g. Screenshot", text: $keyNameText)
                    .textFieldStyle(.roundedBorder)
                    .focused($isKeyNameFocused)
                    .onSubmit { saveKeyName(for: binding) }
                HStack {
                    if viewModel.keyName(for: binding) != nil {
                        Button("Remove Name") {
                            viewModel.setKeyName(nil, for: binding)
                            appState.keyBeingNamed = nil
                        }
                    }
                    Spacer()
                    Button("Cancel") { appState.keyBeingNamed = nil }
                        .keyboardShortcut(.cancelAction)
                    Button("Save") { saveKeyName(for: binding) }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(width: 340)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.windowBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.15)))
            .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        }
    }

    /// How names are written in a .keymap file, from the header's "Show me how"
    private var nameSyntaxCard: some View {
        ZStack {
            Color.black.opacity(0.25)
                .onTapGesture { showsNameSyntax = false }

            VStack(alignment: .leading, spacing: 12) {
                Text("Names in your .keymap file")
                    .font(.headline)
                Text("Put a comment with = right after a binding. The key shows the name instead of its keys:")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("&kp LS(LG(N4)) /* =Screenshot */")
                    Text("&kp LC(LA(LG(C))) /* =Finder */")
                    Text("&my_macro /* =Ä */")
                }
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
                Text("The app follows your edits to the file. A name given with a right-click wins over the file.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Done") { showsNameSyntax = false }
                        .keyboardShortcut(.cancelAction)
                    Button("Choose File…") {
                        showsNameSyntax = false
                        chooseKeymapFile()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(width: 400)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.windowBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.15)))
            .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        }
    }

    private func saveKeyName(for binding: KeyBinding) {
        viewModel.setKeyName(keyNameText, for: binding)
        appState.keyBeingNamed = nil
    }

    // MARK: - Loading files

    private func chooseKeymapFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose your keymap"
        panel.message = "Usually config/<keyboard>.keymap in your zmk-config"
        panel.allowedContentTypes = [UTType(filenameExtension: "keymap") ?? .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if let current = viewModel.currentFilePath {
            panel.directoryURL = URL(fileURLWithPath: current).deletingLastPathComponent()
        }
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadKeymap(from: url.path)
    }

    private func loadDroppedKeymap(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: URL.self) }) else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url = url, url.pathExtension == "keymap" else { return }
            DispatchQueue.main.async {
                loadKeymap(from: url.path)
            }
        }
        return true
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

                // Live Layer Section
                VStack(alignment: .leading, spacing: 8) {
                    Label("Live Layer", systemImage: "dot.radiowaves.left.and.right")
                        .font(.caption.bold())

                    HStack(spacing: 6) {
                        Circle()
                            .fill(appState.liveDeviceName != nil ? Color.green : Color.secondary.opacity(0.4))
                            .frame(width: 7, height: 7)
                        if let device = appState.liveDeviceName {
                            Text("\(device) connected")
                                .font(.caption2)
                            if let layerName = viewModel.liveLayerName {
                                Text("· \(layerName)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Text("No keyboard with layer notifier found")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    Toggle("Follow the keyboard's active layer", isOn: $appState.followLiveLayer)
                        .font(.caption2)
                    Toggle("Show layer number in menu bar", isOn: $appState.showLayerInMenuBar)
                        .font(.caption2)
                    Toggle("Read the keymap from the keyboard (ZMK Studio)", isOn: $appState.readKeymapFromKeyboard)
                        .font(.caption2)

                    Text("Needs the zmk-raw-hid and zmk-keypeek-layer-notifier firmware modules. Reading the keymap also needs ZMK Studio; the file then only adds aliases.")
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
                
                Divider()
                
                // PDF Export Section
                VStack(alignment: .leading, spacing: 10) {
                    Label("PDF Export", systemImage: "doc.fill")
                        .font(.caption.bold())
                    
                    HStack {
                        Text("Save to:")
                            .font(.caption2)
                        
                        Picker("", selection: $appState.exportDirectory) {
                            Text("Desktop").tag("Desktop")
                            Text("Documents").tag("Documents")
                            Text("Downloads").tag("Downloads")
                        }
                        .pickerStyle(.menu)
                        .frame(width: 120)
                        
                        Spacer()
                        
                        if let keymap = viewModel.keymap {
                            Button {
                                PDFExporter.export(keymap: keymap, to: appState.exportDirectory, showRawBindings: true)
                            } label: {
                                Label("Export PDF", systemImage: "arrow.down.doc")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    
                    if viewModel.keymap == nil {
                        Text("Load a keymap first to export")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
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
            
            Button {
                appState.disableHUD()
            } label: {
                Label("Disable HUD Mode", systemImage: "eye.slash")
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
        viewModel.loadKeymap(from: path)
        appState.addRecentKeymap(path)
        // The view model resets the displayed layer when a different file loads
        // Keep menu bar window active
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}



// MARK: - Key View with Tooltip

/// Naming keys with a right-click: in the popover, not in the HUD
struct KeyNaming {
    let name: (KeyBinding) -> Void
    let hasName: (KeyBinding) -> Bool
    let removeName: (KeyBinding) -> Void
}

private struct KeyNamingKey: EnvironmentKey {
    static let defaultValue: KeyNaming? = nil
}

extension EnvironmentValues {
    var keyNaming: KeyNaming? {
        get { self[KeyNamingKey.self] }
        set { self[KeyNamingKey.self] = newValue }
    }
}

struct KeyView: View {
    let binding: KeyBinding
    let isThumbKey: Bool
    /// Held down on the keyboard right now
    var isPressed: Bool = false

    @Environment(\.keyNaming) private var keyNaming

    @State private var isHovered = false
    @State private var showTooltip = false
    
    /// The text to display on the key - alias if present, otherwise parsed display text
    private var displayLabel: String {
        let text = binding.effectiveDisplayText
        // Wrap long aliases after ~8 chars for better fit
        if hasAlias && text.count > 8 {
            // Find a good break point (space, or just split at 8)
            if let spaceIndex = text.firstIndex(of: " "), text.distance(from: text.startIndex, to: spaceIndex) <= 10 {
                var result = text
                result.replaceSubrange(spaceIndex...spaceIndex, with: "\n")
                return result
            }
        }
        return text
    }
    
    /// Whether this key has a user-defined alias
    private var hasAlias: Bool {
        binding.alias != nil
    }
    
    var body: some View {
        ZStack {
            // Key background
            RoundedRectangle(cornerRadius: 10)
                .fill(keyBackgroundColor)
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)

            if isPressed {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor.opacity(0.55))
            }

            // Key border - highlight aliased keys with a subtle accent
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(borderColor, lineWidth: isHovered || isPressed ? 2 : 1)
            
            // Key label
            Text(displayLabel)
                .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                .foregroundColor(textColor)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .padding(4)
        }
        .scaleEffect(isPressed ? 0.94 : 1)
        .animation(.easeOut(duration: 0.08), value: isPressed)
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
        .contextMenu {
            if let keyNaming = keyNaming {
                Button("Name This Key…") { keyNaming.name(binding) }
                if keyNaming.hasName(binding) {
                    Button("Remove Name") { keyNaming.removeName(binding) }
                }
            }
        }
    }
    
    private var borderColor: Color {
        if isHovered || isPressed {
            return Color.accentColor
        }
        return Color.primary.opacity(0.1)
    }
    
    private var keyBackgroundColor: Color {
        // Use displayText (not alias) for color logic so colors stay consistent
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
        let text = displayLabel
        if text.count > 6 {
            return 8
        } else if text.count > 4 {
            return 9
        } else if text.count > 2 {
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

/// One way to name keys in the setup guide
struct GuideWay: View {
    let systemImage: String
    var title: String
    let text: String
    var code: String?

    func replacingTitle(_ title: String) -> GuideWay {
        var way = self
        way.title = title
        return way
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .bold()
                Text(text)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let code = code {
                    Text(code)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.controlBackgroundColor)))
                }
            }
        }
    }
}
