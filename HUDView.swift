import SwiftUI

struct HUDView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var viewModel: KeymapViewModel
    @State private var selectedLayerIndex: Int = 0
    
    var body: some View {
        VStack(spacing: 12) {
            // Discrete drag bar at the top
            Capsule()
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 30, height: 4)
                .padding(.top, 8)
            
            if let keymap = viewModel.keymap {
                // Minimalist and "airy" layer selector
                HStack(spacing: 8) {
                    ForEach(0..<keymap.layers.count, id: \.self) { index in
                        Button(action: { 
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedLayerIndex = index 
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
                        let splitGap: CGFloat = 30
                        
                        let naturalWidth = (maxKeysInRow * keyWidth) + ((maxKeysInRow - 1) * keySpacing) + splitGap
                        let rowCount = CGFloat(keymap.layout.rowCount)
                        let naturalHeight = rowCount * 44 + (rowCount - 1) * keySpacing + (keymap.layout.hasThumbCluster ? 8 : 0)
                        
                        let scale = calculateScale(for: keymap.layout, in: geo.size)
                        
                        KeyboardGridView(layer: layer, layout: keymap.layout)
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
        .overlay(alignment: .bottomTrailing) {
            // Subtle resize handle
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.secondary.opacity(0.3))
                .rotationEffect(.degrees(-45))
                .padding(6)
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
    }
    
    private func calculateScale(for layout: KeyboardLayout, in size: CGSize) -> CGFloat {
        let maxKeysInRow = CGFloat(layout.keysPerRow.max() ?? 10)
        let keyWidth: CGFloat = layout.keysPerRow.first.map { $0 > 10 ? 48 : 54 } ?? 54
        let keySpacing: CGFloat = 3
        let splitGap: CGFloat = 30
        
        let naturalWidth = (maxKeysInRow * keyWidth) + ((maxKeysInRow - 1) * keySpacing) + splitGap
        
        let rowCount = CGFloat(layout.rowCount)
        let naturalHeight = rowCount * 44 + (rowCount - 1) * keySpacing + (layout.hasThumbCluster ? 8 : 0)
        
        let widthScale = size.width / naturalWidth
        let heightScale = size.height / naturalHeight
        
        return min(widthScale, heightScale, 2.0)
    }
}
