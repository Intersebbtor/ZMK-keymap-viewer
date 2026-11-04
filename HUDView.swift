import SwiftUI

struct HUDView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var viewModel: KeymapViewModel

    private var selectedLayerIndex: Int { viewModel.displayedLayerIndex }

    var body: some View {
        VStack(spacing: 12) {
            // Discrete drag bar at the top, with a larger invisible grab area
            Capsule()
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 30, height: 4)
                .frame(width: 120, height: 16)
                .background(WindowDragArea())
                .padding(.top, 2)
            
            if let keymap = viewModel.keymap {
                // Minimalist and "airy" layer selector
                HStack(spacing: 8) {
                    ForEach(0..<keymap.layers.count, id: \.self) { index in
                        Button(action: { 
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                viewModel.selectLayer(index)
                            }
                        }) {
                            Text(keymap.layers[index].name)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    ZStack {
                                        if selectedLayerIndex == index {
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(Color.accentColor)
                                                .shadow(color: Color.accentColor.opacity(0.2), radius: 2, y: 1)
                                        } else {
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(Color.primary.opacity(0.03))
                                        }
                                    }
                                )
                                .foregroundColor(selectedLayerIndex == index ? .white : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                
                // The keyboard adapts to the remaining space
                if let layer = keymap.layers[safe: selectedLayerIndex] {
                    GeometryReader { geo in
                        let maxKeysInRow = CGFloat(keymap.layout.keysPerRow.max() ?? 10)
                        let keyWidth: CGFloat = keymap.layout.keysPerRow.first.map { $0 > 10 ? 48 : 54 } ?? 54
                        let keySpacing: CGFloat = 3
                        let splitGap: CGFloat = keymap.layout.isSplit ? 30 : 0
                        
                        let naturalWidth = (maxKeysInRow * keyWidth) + ((maxKeysInRow - 1) * keySpacing) + splitGap
                        let rowCount = CGFloat(keymap.layout.rowCount)
                        let naturalHeight = rowCount * 44 + (rowCount - 1) * keySpacing + (keymap.layout.hasThumbCluster ? 8 : 0)
                        
                        let scale = calculateScale(for: keymap.layout, in: geo.size)
                        
                        KeyboardGridView(layer: layer, layout: keymap.layout, pressedPositions: viewModel.pressedPositions)
                            .frame(width: naturalWidth, height: naturalHeight)
                            .scaleEffect(scale, anchor: .center)
                            .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    }
                    .padding([.horizontal, .bottom], 12)
                }
            } else {
                Text("No Keymap Loaded")
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // Typing speed in the corner next to the drag bar
        .overlay(alignment: .topTrailing) {
            if appState.showWPMInHUD, appState.liveDeviceName != nil {
                WPMView(wpm: viewModel.wpm, history: viewModel.wpmHistory)
                    .padding(.top, 10)
                    .padding(.trailing, 18)
            }
        }
        .background(
            ZStack {
                if appState.hudUseMaterial {
                    VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                } else {
                    Color(NSColor.windowBackgroundColor).opacity(0.95)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
        )
        // Removed padding(10) to align resize area with visible border
        .opacity(appState.isHUDInactive ? 0.15 : appState.hudOpacity)
        .scaleEffect(appState.isHUDInactive ? 0.98 : 1.0)
        .animation(.easeInOut(duration: 0.8), value: appState.isHUDInactive)
        // Outside the fade so the zones stay grabbable while the HUD is faded
        .overlay(WindowResizeEdges())
    }
    
    private func calculateScale(for layout: KeyboardLayout, in size: CGSize) -> CGFloat {
        let maxKeysInRow = CGFloat(layout.keysPerRow.max() ?? 10)
        let keyWidth: CGFloat = layout.keysPerRow.first.map { $0 > 10 ? 48 : 54 } ?? 54
        let keySpacing: CGFloat = 3
        let splitGap: CGFloat = layout.isSplit ? 30 : 0
        
        let naturalWidth = (maxKeysInRow * keyWidth) + ((maxKeysInRow - 1) * keySpacing) + splitGap
        
        let rowCount = CGFloat(layout.rowCount)
        let naturalHeight = rowCount * 44 + (rowCount - 1) * keySpacing + (layout.hasThumbCluster ? 8 : 0)
        
        let widthScale = size.width / naturalWidth
        let heightScale = size.height / naturalHeight
        
        return min(widthScale, heightScale, 2.0)
    }
}

/// Words per minute with a graph of the last 30 seconds, like the nice!view
struct WPMView: View {
    let wpm: Int
    let history: [Int]

    var body: some View {
        HStack(spacing: 6) {
            WPMGraph(values: history)
                .stroke(Color.accentColor.opacity(0.8), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
                .frame(width: 54, height: 14)
            Text("\(wpm)")
                .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                .frame(minWidth: 22, alignment: .trailing)
            Text("WPM")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
        }
        .help("Typing speed: five key presses make a word, averaged over the last five seconds")
    }
}

/// A line over the samples, scaled to the highest one (at least 40 WPM, so
/// slow typing doesn't fill the graph)
struct WPMGraph: Shape {
    let values: [Int]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1 else { return path }
        let top = Double(max(values.max() ?? 0, 40))
        let step = rect.width / CGFloat(WPMMeter.historyLength - 1)
        // Right-aligned, so new samples come in on the right
        let startX = rect.maxX - CGFloat(values.count - 1) * step
        for (index, value) in values.enumerated() {
            let point = CGPoint(x: startX + CGFloat(index) * step, y: rect.maxY - CGFloat(Double(value) / top) * rect.height)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

