import Foundation

/// Turns a keymap read from the keyboard into the viewer's Keymap. Each
/// binding is written back as ZMK keymap source ("&kp Q", "&mt LSHFT Z"), so
/// KeymapParser labels it exactly like a binding from a .keymap file.
enum StudioKeymapConverter {

    /// `aliases` and `fallbackLayerNames` come from the keymap file, by
    /// layer index and key position
    static func keymap(from snapshot: StudioSnapshot, aliases: [[String?]] = [], fallbackLayerNames: [String] = []) -> Keymap? {
        guard let firstLayer = snapshot.layers.first, !firstLayer.bindings.isEmpty else { return nil }

        let keyCount = firstLayer.bindings.count
        let rows = rowLengths(of: snapshot.layout, keyCount: keyCount)

        let layers = snapshot.layers.enumerated().map { index, layer -> KeymapLayer in
            let codes = layer.bindings.map { bindingCode($0, behavior: snapshot.behaviors[UInt32(bitPattern: $0.behaviorID)]) }
            let layerAliases = aliases.indices.contains(index) ? aliases[index] : []
            let source = sourceLines(codes: codes, aliases: layerAliases, rows: rows)
            return KeymapLayer(
                name: !layer.name.isEmpty ? layer.name : fallbackLayerNames[safe: index] ?? "Layer \(index)",
                bindings: KeymapParser.parseBindings(from: source),
                rowCount: rows.count,
                columnCount: rows.max() ?? 0
            )
        }

        let layout = KeyboardLayout.create(
            keyCount: keyCount,
            keysPerRow: rows,
            detectedName: snapshot.deviceName.isEmpty ? nil : snapshot.deviceName,
            isSplit: isSplit(snapshot.layout, rows: rows)
        )
        return Keymap(layers: layers, layout: layout)
    }

    /// One source line per row, so parseBindings keeps the rows
    private static func sourceLines(codes: [String], aliases: [String?], rows: [Int]) -> String {
        var lines: [String] = []
        var index = 0
        for length in rows {
            let line = (index..<min(index + length, codes.count)).map { position -> String in
                guard aliases.indices.contains(position), let alias = aliases[position] else { return codes[position] }
                return "\(codes[position]) /* =\(alias) */"
            }
            lines.append(line.joined(separator: " "))
            index += length
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Layout

    /// Keys come in reading order: a new row starts where x jumps back left.
    /// Without a physical layout, rows of 10 keys.
    static func rowLengths(of layout: StudioPhysicalLayout?, keyCount: Int) -> [Int] {
        guard let keys = layout?.keys, keys.count == keyCount, keyCount > 0 else {
            return stride(from: 0, to: keyCount, by: 10).map { min(10, keyCount - $0) }
        }
        var rows: [Int] = [1]
        for index in 1..<keys.count {
            if keys[index].x < keys[index - 1].x {
                rows.append(1)
            } else {
                rows[rows.count - 1] += 1
            }
        }
        return rows
    }

    /// Split when the widest gap between neighbors in the first row is more
    /// than a key wide
    static func isSplit(_ layout: StudioPhysicalLayout?, rows: [Int]) -> Bool {
        guard let keys = layout?.keys, let firstRow = rows.first, firstRow > 1, keys.count >= firstRow else { return true }
        let gaps = (1..<firstRow).map { keys[$0].x - (keys[$0 - 1].x + keys[$0 - 1].width) }
        return (gaps.max() ?? 0) > 100
    }

    // MARK: - Bindings

    static func bindingCode(_ binding: StudioBinding, behavior: StudioBehavior?) -> String {
        guard let behavior = behavior else { return "&none" }
        let p1 = binding.param1
        let p2 = binding.param2

        switch behavior.displayName {
        case "Key Press": return "&kp \(HIDUsage.name(p1))"
        case "Key Toggle": return "&kt \(HIDUsage.name(p1))"
        case "Sticky Key": return "&sk \(HIDUsage.name(p1))"
        case "Mod-Tap": return "&mt \(HIDUsage.name(p1)) \(HIDUsage.name(p2))"
        case "Layer-Tap": return "&lt \(p1) \(HIDUsage.name(p2))"
        case "Momentary Layer": return "&mo \(p1)"
        case "Toggle Layer": return "&tog \(p1)"
        case "To Layer": return "&to \(p1)"
        case "Sticky Layer": return "&sl \(p1)"
        case "Transparent": return "&trans"
        case "None": return "&none"
        case "Bluetooth": return "&bt \(bluetoothCommand(p1, p2))"
        case "Output Selection": return "&out \(["OUT_TOG", "OUT_USB", "OUT_BLE"][safe: Int(p1)] ?? "\(p1)")"
        case "Reset": return "&sys_reset"
        case "Bootloader": return "&bootloader"
        case "Studio Unlock": return "&studio_unlock"
        case "Caps Word": return "&caps_word"
        case "Key Repeat": return "&key_repeat"
        case "Grave/Escape": return "&gresc"
        default:
            // Custom behaviors (hold-taps, macros) keep their own name and get
            // their parameters formatted by the kinds in their metadata
            let name = behavior.displayName.replacingOccurrences(of: " ", with: "_")
            let params = [(behavior.param1, p1), (behavior.param2, p2)].compactMap { kind, value -> String? in
                switch kind {
                case .none: return nil
                case .hidUsage: return HIDUsage.name(value)
                case .layer, .number: return "\(value)"
                }
            }
            return (["&\(name)"] + params).joined(separator: " ")
        }
    }

    private static func bluetoothCommand(_ command: UInt32, _ profile: UInt32) -> String {
        switch command {
        case 0: return "BT_CLR"
        case 1: return "BT_NXT"
        case 2: return "BT_PRV"
        case 3: return "BT_SEL \(profile)"
        case 4: return "BT_CLR_ALL"
        case 5: return "BT_DISC \(profile)"
        default: return "\(command)"
        }
    }
}

/// ZMK's encoding of key codes: (implicit modifiers << 24) | (usage page << 16) | usage id
enum HIDUsage {
    static func name(_ encoded: UInt32) -> String {
        let modifiers = UInt8(encoded >> 24)
        let page = (encoded >> 16) & 0xFF
        let id = encoded & 0xFFFF

        var base: String
        switch page {
        case 0x07: base = keyboard[id] ?? String(format: "0x%02X", id)
        case 0x0C: base = consumer[id] ?? String(format: "C_0x%02X", id)
        default: base = String(format: "0x%06X", encoded & 0xFFFFFF)
        }

        // Shift alone plus a key is written as the shifted symbol (EXCL, not
        // LS(N1)). With other modifiers it is a shortcut: ⇧⌘4, not ⌘$.
        if modifiers == 0x02 || modifiers == 0x20, page == 0x07, let shifted = shiftedSymbols[id] {
            return shifted
        }
        // Nested so the label reads in the macOS order ⌃⌥⇧⌘
        for (bit, wrapper) in modifierWrappers.reversed() where modifiers & bit != 0 {
            base = "\(wrapper)(\(base))"
        }
        return base
    }

    /// Outermost first
    private static let modifierWrappers: [(UInt8, String)] = [
        (0x01, "LC"), (0x10, "RC"), (0x04, "LA"), (0x40, "RA"),
        (0x02, "LS"), (0x20, "RS"), (0x08, "LG"), (0x80, "RG"),
    ]

    private static let shiftedSymbols: [UInt32: String] = [
        0x1E: "EXCL", 0x1F: "AT", 0x20: "HASH", 0x21: "DLLR", 0x22: "PRCNT", 0x23: "CARET",
        0x24: "AMPS", 0x25: "STAR", 0x26: "LPAR", 0x27: "RPAR", 0x2D: "UNDER", 0x2E: "PLUS",
        0x2F: "LBRC", 0x30: "RBRC", 0x31: "PIPE", 0x33: "COLON", 0x34: "DQT", 0x35: "TILDE",
        0x36: "LT", 0x37: "GT", 0x38: "QMARK",
    ]

    private static let keyboard: [UInt32: String] = {
        var names: [UInt32: String] = [:]
        for (offset, letter) in "ABCDEFGHIJKLMNOPQRSTUVWXYZ".enumerated() {
            names[0x04 + UInt32(offset)] = String(letter)
        }
        for digit in 1...9 {
            names[0x1D + UInt32(digit)] = "N\(digit)"
        }
        names[0x27] = "N0"
        for number in 1...12 {
            names[0x39 + UInt32(number)] = "F\(number)"
        }
        for number in 13...24 {
            names[0x5B + UInt32(number)] = "F\(number)"
        }
        for digit in 1...9 {
            names[0x58 + UInt32(digit)] = "KP_N\(digit)"
        }
        let named: [UInt32: String] = [
            0x28: "RET", 0x29: "ESC", 0x2A: "BSPC", 0x2B: "TAB", 0x2C: "SPACE", 0x2D: "MINUS",
            0x2E: "EQUAL", 0x2F: "LBKT", 0x30: "RBKT", 0x31: "BSLH", 0x32: "NUHS", 0x33: "SEMI",
            0x34: "SQT", 0x35: "GRAVE", 0x36: "COMMA", 0x37: "DOT", 0x38: "FSLH", 0x39: "CAPS",
            0x46: "PSCRN", 0x47: "SLCK", 0x48: "PAUSE_BREAK", 0x49: "INS", 0x4A: "HOME",
            0x4B: "PG_UP", 0x4C: "DEL", 0x4D: "END", 0x4E: "PG_DN", 0x4F: "RIGHT", 0x50: "LEFT",
            0x51: "DOWN", 0x52: "UP", 0x53: "KP_NUM", 0x54: "KP_SLASH", 0x55: "KP_MULTIPLY",
            0x56: "KP_MINUS", 0x57: "KP_PLUS", 0x58: "KP_ENTER", 0x62: "KP_N0", 0x63: "KP_DOT",
            0x64: "NUBS", 0x65: "K_APP", 0x67: "KP_EQUAL",
            0x7F: "K_MUTE", 0x80: "K_VOLUME_UP", 0x81: "K_VOLUME_DOWN",
            0xE0: "LCTRL", 0xE1: "LSHFT", 0xE2: "LALT", 0xE3: "LGUI",
            0xE4: "RCTRL", 0xE5: "RSHFT", 0xE6: "RALT", 0xE7: "RGUI",
        ]
        names.merge(named) { _, new in new }
        return names
    }()

    private static let consumer: [UInt32: String] = [
        0xE9: "C_VOL_UP", 0xEA: "C_VOL_DN", 0xE2: "C_MUTE", 0xCD: "C_PP", 0xB5: "C_NEXT",
        0xB6: "C_PREV", 0xB7: "C_STOP", 0x6F: "C_BRI_UP", 0x70: "C_BRI_DN", 0xB8: "C_EJECT",
    ]
}
