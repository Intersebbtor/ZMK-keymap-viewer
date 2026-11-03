import Foundation

/// A Raw HID packet sent by the zmk-keypeek-layer-notifier firmware module
/// (usage page 0xFF60, usage 0x61).
enum LayerPacket: Equatable {
    /// Bitmasks of the default and the currently active layers (bit N = layer N).
    case layerState(defaultLayers: UInt32, activeLayers: UInt32)
    /// The key at `position` was pressed or released.
    case keyEvent(position: Int, pressed: Bool)

    static let layerStateMarker: UInt8 = 0xFF
    static let keyEventMarker: UInt8 = 0xF1

    /// Decodes one report. Returns nil for unknown or truncated reports
    /// (e.g. 0xF2, the Studio RPC tunnel of the same module).
    static func decode(_ bytes: [UInt8]) -> LayerPacket? {
        guard let marker = bytes.first else { return nil }

        switch marker {
        case layerStateMarker:
            // [0xFF, 0x04, default mask (u32 LE), active mask (u32 LE)]
            guard bytes.count >= 10 else { return nil }
            return .layerState(
                defaultLayers: uint32LittleEndian(bytes, at: 2),
                activeLayers: uint32LittleEndian(bytes, at: 6)
            )
        case keyEventMarker:
            // [0xF1, 0x00, position, pressed]
            guard bytes.count >= 4 else { return nil }
            return .keyEvent(position: Int(bytes[2]), pressed: bytes[3] == 1)
        default:
            return nil
        }
    }

    private static func uint32LittleEndian(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { value, i in
            value | UInt32(bytes[offset + i]) << (8 * i)
        }
    }
}

enum ActiveLayerResolver {
    /// The highest active layer is the one ZMK looks up keys on first, so it is
    /// the layer to show. Layer 0 counts as always active.
    static func highestLayer(activeLayers: UInt32, defaultLayers: UInt32) -> Int {
        let mask = activeLayers | defaultLayers | 1
        return UInt32.bitWidth - 1 - mask.leadingZeroBitCount
    }
}

enum MenuBarSymbol {
    static let defaultName = "keyboard"
    /// SF Symbols has numbered squares for 0...50
    private static let numberedRange = 0...50

    /// The live layer number, including 0 for the base layer, so the icon
    /// doesn't switch shape on every layer change. The keyboard icon only
    /// without a connected keyboard or beyond the numbered symbols.
    /// Always one fixed-width symbol, so the menu bar item never changes size.
    static func name(liveIndex: Int?, showLayer: Bool) -> String {
        guard showLayer, let index = liveIndex, numberedRange.contains(index) else {
            return defaultName
        }
        return "\(index).square.fill"
    }
}

/// Which layer the views show: the keyboard's live layer, unless the user
/// picked a tab after the last live change.
struct LayerSelection: Equatable {
    /// The layer shown in the menu and the HUD.
    private(set) var displayedIndex: Int = 0
    /// The keyboard's highest active layer, nil while no keyboard reports one.
    /// Can exceed the parsed layer count when the keymap file is out of date.
    private(set) var liveIndex: Int?

    mutating func selectManually(_ index: Int) {
        displayedIndex = index
    }

    /// A manual selection stays until the keyboard reports the next change.
    /// Layers the keymap file does not know are tracked but not displayed.
    mutating func applyLive(_ index: Int, layerCount: Int, follow: Bool) {
        liveIndex = index
        if follow, index < layerCount {
            displayedIndex = index
        }
    }

    mutating func clearLive() {
        liveIndex = nil
    }

    /// For a newly loaded keymap: start on the live layer if it exists.
    mutating func reset(layerCount: Int) {
        if let live = liveIndex, live < layerCount {
            displayedIndex = live
        } else {
            displayedIndex = 0
        }
    }

    /// For a reloaded keymap that may have lost layers.
    mutating func clamp(layerCount: Int) {
        if displayedIndex >= layerCount {
            displayedIndex = max(layerCount - 1, 0)
        }
    }
}
