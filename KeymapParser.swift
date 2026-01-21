import Foundation

/// Represents a single key binding with both display text and raw code
struct KeyBinding: Identifiable, Equatable {
    let id = UUID()
    let displayText: String   // Human-readable display (e.g., "Q", "CTRL+Q")
    let rawCode: String       // Original keymap code (e.g., "&long_MT RIGHT_CONTROL Q")
    let row: Int
    let column: Int
    
    static func == (lhs: KeyBinding, rhs: KeyBinding) -> Bool {
        return lhs.id == rhs.id
    }
}

/// Represents a layer in the keymap
struct KeymapLayer: Identifiable {
    let id = UUID()
    let name: String
    let bindings: [KeyBinding]
    let rowCount: Int
    let columnCount: Int
}

/// Detected keyboard layout configuration
struct KeyboardLayout: Equatable {
    let totalKeys: Int
    let keysPerRow: [Int]     // Number of keys in each row
    let rowCount: Int
    let hasThumbCluster: Bool
    let thumbKeysCount: Int
    let name: String          // e.g., "Sweep", "Corne", "Unknown"
    
    static let sweep = KeyboardLayout(
        totalKeys: 34,
        keysPerRow: [10, 10, 10, 4],
        rowCount: 4,
        hasThumbCluster: true,
        thumbKeysCount: 4,
        name: "Sweep/Cradio"
    )
    
    static let corne = KeyboardLayout(
        totalKeys: 42,
        keysPerRow: [12, 12, 12, 6],
        rowCount: 4,
        hasThumbCluster: true,
        thumbKeysCount: 6,
        name: "Corne"
    )
    
    static func detect(fromKeyCount count: Int, keysPerRow: [Int]) -> KeyboardLayout {
        // Try to match known layouts
        if count == 34 {
            return .sweep
        } else if count == 42 {
            return .corne
        }
        
        // Create a custom layout based on detected keys
        let rowCount = keysPerRow.count
        let thumbKeys = keysPerRow.last ?? 0
        return KeyboardLayout(
            totalKeys: count,
            keysPerRow: keysPerRow,
            rowCount: rowCount,
            hasThumbCluster: thumbKeys < (keysPerRow.first ?? 0),
            thumbKeysCount: thumbKeys,
            name: "Custom (\(count) keys)"
        )
    }
}

/// Complete parsed keymap with all layers and layout info
struct Keymap {
    var layers: [KeymapLayer]
    var layout: KeyboardLayout
    var behaviors: [String: String]  // behavior name -> description
    var macros: [String: String]     // macro name -> description
    
    init(layers: [KeymapLayer] = [], layout: KeyboardLayout = .sweep, behaviors: [String: String] = [:], macros: [String: String] = [:]) {
        self.layers = layers
        self.layout = layout
        self.behaviors = behaviors
        self.macros = macros
    }
}

class KeymapParser {
    
    /// Parse a ZMK keymap file and return a complete Keymap structure
    static func parse(from data: String) -> Keymap? {
        // Remove comments before processing
        let cleanedData = removeComments(from: data)
        
        var layers: [KeymapLayer] = []
        var behaviors: [String: String] = [:]
        var macros: [String: String] = [:]
        
        // Parse behaviors
        behaviors = parseBehaviors(from: cleanedData)
        
        // Parse macros
        macros = parseMacros(from: cleanedData)
        
        // Find the keymap section
        guard let keymapRange = findKeymapSection(in: cleanedData) else {
            print("Could not find keymap section")
            return nil
        }
        
        let keymapContent = String(cleanedData[keymapRange])
        
        // Parse each layer
        layers = parseLayers(from: keymapContent)
        
        // Detect layout from first layer
        let layout: KeyboardLayout
        if let firstLayer = layers.first {
            let keysPerRow = calculateKeysPerRow(bindings: firstLayer.bindings)
            layout = KeyboardLayout.detect(fromKeyCount: firstLayer.bindings.count, keysPerRow: keysPerRow)
            print("[KeymapParser] Detected: \(layout.name) with \(layers.count) layers, \(firstLayer.bindings.count) keys")
        } else {
            print("[KeymapParser] No layers found, defaulting to Sweep")
            layout = .sweep
        }
        
        return Keymap(layers: layers, layout: layout, behaviors: behaviors, macros: macros)
    }
    
    /// Remove C-style comments (// and /* */) from the data
    private static func removeComments(from data: String) -> String {
        var result = ""
        var i = data.startIndex
        
        while i < data.endIndex {
            let nextI = data.index(after: i)
            
            // Check for C++ style comment (//)
            if i < data.index(data.endIndex, offsetBy: -1) && 
               data[i] == "/" && data[nextI] == "/" {
                // Skip until end of line
                while i < data.endIndex && data[i] != "\n" {
                    i = data.index(after: i)
                }
                // Keep the newline
                if i < data.endIndex {
                    result.append("\n")
                    i = data.index(after: i)
                }
                continue
            }
            
            // Check for C style comment (/* */)
            if i < data.index(data.endIndex, offsetBy: -1) && 
               data[i] == "/" && data[nextI] == "*" {
                // Skip until */
                i = data.index(after: nextI)
                while i < data.index(data.endIndex, offsetBy: -1) {
                    if data[i] == "*" && data[data.index(after: i)] == "/" {
                        i = data.index(after: data.index(after: i))
                        break
                    }
                    // Preserve newlines within comments for line tracking
                    if data[i] == "\n" {
                        result.append("\n")
                    }
                    i = data.index(after: i)
                }
                continue
            }
            
            result.append(data[i])
            i = data.index(after: i)
        }
        
        return result
    }
    
    private static func findKeymapSection(in data: String) -> Range<String.Index>? {
        // Find "keymap {" section
        guard let keymapStart = data.range(of: "keymap\\s*\\{", options: .regularExpression) else {
            return nil
        }
        
        // Find matching closing brace
        var braceCount = 0
        var foundFirst = false
        var endIndex = keymapStart.upperBound
        
        for i in data.indices[keymapStart.lowerBound...] {
            let char = data[i]
            if char == "{" {
                braceCount += 1
                foundFirst = true
            } else if char == "}" {
                braceCount -= 1
                if foundFirst && braceCount == 0 {
                    endIndex = data.index(after: i)
                    break
                }
            }
        }
        
        return keymapStart.lowerBound..<endIndex
    }
    
    private static func parseBehaviors(from data: String) -> [String: String] {
        var behaviors: [String: String] = [:]
        
        // Find behaviors section
        guard data.range(of: "behaviors\\s*\\{", options: .regularExpression) != nil else {
            return behaviors
        }
        
        // Extract behavior names and labels
        let pattern = "(\\w+):\\s*\\w+\\s*\\{[^}]*label\\s*=\\s*\"([^\"]+)\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return behaviors
        }
        
        let nsData = data as NSString
        let matches = regex.matches(in: data, options: [], range: NSRange(location: 0, length: nsData.length))
        
        for match in matches {
            if match.numberOfRanges >= 3 {
                let name = nsData.substring(with: match.range(at: 1))
                let label = nsData.substring(with: match.range(at: 2))
                behaviors[name] = label
            }
        }
        
        return behaviors
    }
    
    private static func parseMacros(from data: String) -> [String: String] {
        var macros: [String: String] = [:]
        
        // Find macros section
        guard data.contains("macros") else {
            return macros
        }
        
        // Extract macro names and labels
        let pattern = "(\\w+):\\s*\\w+\\s*\\{[^}]*label\\s*=\\s*\"([^\"]+)\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return macros
        }
        
        // Look in macros section specifically
        if let macroStart = data.range(of: "macros\\s*\\{", options: .regularExpression) {
            let searchRange = macroStart.lowerBound..<data.endIndex
            let nsData = data as NSString
            let nsRange = NSRange(searchRange, in: data)
            let matches = regex.matches(in: data, options: [], range: nsRange)
            
            for match in matches {
                if match.numberOfRanges >= 3 {
                    let name = nsData.substring(with: match.range(at: 1))
                    let label = nsData.substring(with: match.range(at: 2))
                    macros[name] = label
                }
            }
        }
        
        return macros
    }
    
    private static func parseLayers(from keymapContent: String) -> [KeymapLayer] {
        var layers: [KeymapLayer] = []
        
        // Pattern to match layer definitions
        // Use .*? (non-greedy) to match any content between { and bindings,
        // including comments and whitespace. This handles keymaps with or without
        // label/display-name, and with comments before bindings.
        let layerPattern = "(\\w+)\\s*\\{.*?(?:(?:label|display-name)\\s*=\\s*\"([^\"]*)\"\\s*;)?.*?bindings\\s*=\\s*<(.*?)>\\s*;"
        guard let regex = try? NSRegularExpression(pattern: layerPattern, options: [.dotMatchesLineSeparators]) else {
            return layers
        }
        
        let nsContent = keymapContent as NSString
        let matches = regex.matches(in: keymapContent, options: [], range: NSRange(location: 0, length: nsContent.length))
        
        for match in matches {
            guard match.numberOfRanges >= 4 else { continue }
            
            let layerName = match.range(at: 2).location != NSNotFound
                ? nsContent.substring(with: match.range(at: 2))
                : nsContent.substring(with: match.range(at: 1))
            
            let bindingsRaw = nsContent.substring(with: match.range(at: 3))
            let bindings = parseBindings(from: bindingsRaw)
            
            let keysPerRow = calculateKeysPerRow(bindings: bindings)
            let rowCount = keysPerRow.count
            let columnCount = keysPerRow.max() ?? 0
            
            let layer = KeymapLayer(
                name: layerName,
                bindings: bindings,
                rowCount: rowCount,
                columnCount: columnCount
            )
            layers.append(layer)
        }
        
        return layers
    }
    
    /// Strip C-style line comments (// ...) from a line
    private static func stripLineComment(_ line: String) -> String {
        if let commentRange = line.range(of: "//") {
            return String(line[..<commentRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        return line
    }
    
    private static func parseBindings(from bindingsRaw: String) -> [KeyBinding] {
        var bindings: [KeyBinding] = []
        
        // Split by newlines first to preserve row structure
        let lines = bindingsRaw.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { stripLineComment($0) }  // Strip // comments from each line
            .filter { !$0.isEmpty }
        
        var currentRow = 0
        
        for line in lines {
            let tokens = tokenizeBindings(line)
            
            // If this line has bindings, add them to the current row
            if !tokens.isEmpty {
                for (colIndex, rawCode) in tokens.enumerated() {
                    let displayText = parseDisplayText(from: rawCode)
                    
                    let binding = KeyBinding(
                        displayText: displayText,
                        rawCode: rawCode,
                        row: currentRow,
                        column: colIndex
                    )
                    bindings.append(binding)
                }
                currentRow += 1
            }
        }
        
        return bindings
    }
    
    private static func tokenizeBindings(_ input: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var parenDepth = 0
        
        let chars = Array(input)
        var i = 0
        
        while i < chars.count {
            let char = chars[i]
            
            if char == "&" {
                if !current.trimmingCharacters(in: .whitespaces).isEmpty {
                    tokens.append(current.trimmingCharacters(in: .whitespaces))
                }
                current = "&"
            } else if char == "(" {
                parenDepth += 1
                current.append(char)
            } else if char == ")" {
                parenDepth -= 1
                current.append(char)
            } else if char == " " && parenDepth == 0 && !current.isEmpty {
                // Space outside parentheses - check if next non-space is &
                var nextNonSpace = i + 1
                while nextNonSpace < chars.count && chars[nextNonSpace] == " " {
                    nextNonSpace += 1
                }
                if nextNonSpace < chars.count && chars[nextNonSpace] == "&" {
                    // End of current token
                    if !current.trimmingCharacters(in: .whitespaces).isEmpty {
                        tokens.append(current.trimmingCharacters(in: .whitespaces))
                    }
                    current = ""
                } else {
                    current.append(char)
                }
            } else {
                current.append(char)
            }
            
            i += 1
        }
        
        if !current.trimmingCharacters(in: .whitespaces).isEmpty {
            tokens.append(current.trimmingCharacters(in: .whitespaces))
        }
        
        return tokens
    }
    
    private static func guessKeysPerRow(totalKeys: Int) -> [Int] {
        switch totalKeys {
        case 34:  // Sweep
            return [10, 10, 10, 4]
        case 42:  // Corne
            return [12, 12, 12, 6]
        case 36:  // Sweep with extra keys
            return [10, 10, 10, 6]
        case 44:  // Corne with extra keys
            return [12, 12, 12, 8]
        case 58:  // Lily58
            return [12, 12, 12, 12, 10]
        case 56:  // Sofle
            return [12, 12, 12, 12, 8]
        default:
            // Generic split keyboard guess
            if totalKeys % 2 == 0 {
                let half = totalKeys / 2
                if half >= 17 && half <= 21 {
                    // Likely 3 rows + thumb cluster
                    let mainRows = (half - 3) / 3
                    let thumbKeys = half - (mainRows * 3)
                    return [mainRows * 2, mainRows * 2, mainRows * 2, thumbKeys * 2]
                }
            }
            // Default to even distribution
            let rowCount = max(1, (totalKeys + 9) / 10)
            let keysPerRow = totalKeys / rowCount
            let remainder = totalKeys % rowCount
            var result = Array(repeating: keysPerRow, count: rowCount)
            if remainder > 0 {
                result[rowCount - 1] += remainder
            }
            return result
        }
    }
    
    private static func calculateKeysPerRow(bindings: [KeyBinding]) -> [Int] {
        var rowCounts: [Int: Int] = [:]
        for binding in bindings {
            rowCounts[binding.row, default: 0] += 1
        }
        
        let maxRow = rowCounts.keys.max() ?? 0
        var result: [Int] = []
        for row in 0...maxRow {
            result.append(rowCounts[row] ?? 0)
        }
        return result
    }
    
    private static func parseDisplayText(from rawCode: String) -> String {
        // Remove the leading &
        let code = rawCode.hasPrefix("&") ? String(rawCode.dropFirst()) : rawCode
        let parts = code.split(separator: " ").map(String.init)
        
        guard !parts.isEmpty else { return rawCode }
        
        let behavior = parts[0]
        
        // Handle different binding types
        switch behavior {
        case "kp":
            // Key press: &kp KEY
            if parts.count > 1 {
                return formatKey(parts[1])
            }
        case "mt":
            // Mod-tap: &mt MOD KEY
            if parts.count > 2 {
                let mod = formatModifier(parts[1])
                let key = formatKey(parts[2])
                return "\(mod)\n\(key)"
            }
        case "lt":
            // Layer-tap: &lt LAYER KEY
            if parts.count > 2 {
                let layer = parts[1]
                let key = formatKey(parts[2])
                return "L\(layer)\n\(key)"
            }
        case "mo":
            // Momentary layer: &mo LAYER
            if parts.count > 1 {
                return "MO\(parts[1])"
            }
        case "tog":
            // Toggle layer: &tog LAYER
            if parts.count > 1 {
                return "TG\(parts[1])"
            }
        case "trans":
            return "▽"
        case "none":
            return "✕"
        case "bt":
            // Bluetooth: &bt BT_SEL 0
            if parts.count > 1 {
                let btAction = parts[1]
                if btAction == "BT_SEL" && parts.count > 2 {
                    return "BT\(parts[2])"
                } else if btAction == "BT_CLR" {
                    return "BT CLR"
                }
                return btAction.replacingOccurrences(of: "BT_", with: "")
            }
        case "sys_reset":
            return "RESET"
        case "bootloader":
            return "BOOT"
        case "studio_unlock":
            return "STUDIO"
        default:
            // Check for custom behaviors like long_MT, short_LT
            if behavior.contains("MT") || behavior.contains("mt") {
                if parts.count > 2 {
                    let mod = formatModifier(parts[1])
                    let key = formatKey(parts[2])
                    return "\(mod)\n\(key)"
                }
            }
            if behavior.contains("LT") || behavior.contains("lt") {
                if parts.count > 2 {
                    let layer = parts[1]
                    let key = formatKey(parts[2])
                    return "L\(layer)\n\(key)"
                }
            }
            // Macros and other custom behaviors
            if parts.count == 1 {
                return behavior.uppercased()
            }
            // Return the last part as the key if available
            if let lastPart = parts.last {
                return formatKey(lastPart)
            }
        }
        
        return rawCode
    }
    
    private static func formatKey(_ key: String) -> String {
        // Remove common prefixes and format nicely
        let formatted = key
            .replacingOccurrences(of: "NUMBER_", with: "")
            .replacingOccurrences(of: "KP_", with: "")
            .replacingOccurrences(of: "K_", with: "")
        
        // Handle special keys
        let specialKeys: [String: String] = [
            "BACKSPACE": "⌫",
            "BSPC": "⌫",
            "SPACE": "␣",
            "SPC": "␣",
            "TAB": "⇥",
            "RETURN": "⏎",
            "RET": "⏎",
            "ENTER": "⏎",
            "ESCAPE": "ESC",
            "ESC": "ESC",
            "DELETE": "DEL",
            "DEL": "DEL",
            "LEFT": "←",
            "RIGHT": "→",
            "UP": "↑",
            "DOWN": "↓",
            "SEMICOLON": ";",
            "SEMI": ";",
            "COMMA": ",",
            "DOT": ".",
            "PERIOD": ".",
            "SLASH": "/",
            "FSLH": "/",
            "BACKSLASH": "\\",
            "BSLH": "\\",
            "MINUS": "-",
            "EQUAL": "=",
            "PLUS": "+",
            "LBKT": "[",
            "RBKT": "]",
            "LBRC": "{",
            "RBRC": "}",
            "LPAR": "(",
            "RPAR": ")",
            "SQT": "'",
            "SINGLE_QUOTE": "'",
            "DQT": "\"",
            "DOUBLE_QUOTES": "\"",
            "GRAVE": "`",
            "TILDE": "~",
            "EXCLAMATION": "!",
            "EXCL": "!",
            "AT_SIGN": "@",
            "AT": "@",
            "HASH": "#",
            "POUND": "#",
            "DLLR": "$",
            "DOLLAR": "$",
            "PRCNT": "%",
            "PERCENT": "%",
            "CARET": "^",
            "AMPS": "&",
            "AMPERSAND": "&",
            "STAR": "*",
            "ASTRK": "*",
            "MULTIPLY": "*",
            "VOLUME_UP": "VOL+",
            "VOLUME_DOWN": "VOL-",
            "MUTE": "MUTE",
            "N0": "0", "N1": "1", "N2": "2", "N3": "3", "N4": "4",
            "N5": "5", "N6": "6", "N7": "7", "N8": "8", "N9": "9"
        ]
        
        if let special = specialKeys[formatted.uppercased()] {
            return special
        }
        
        // Handle modifier combos like LS(LG(NUMBER_4))
        if formatted.contains("(") {
            return parseModifiedKey(formatted)
        }
        
        return formatted.uppercased()
    }
    
    private static func parseModifiedKey(_ key: String) -> String {
        // Extract the innermost key and all modifiers
        var modifiers: [String] = []
        var current = key
        
        let modPattern = "(L[SCAG]|R[SCAG]|LC|RC|LA|RA|LG|RG|LS|RS)\\((.+)\\)"
        
        while let regex = try? NSRegularExpression(pattern: modPattern, options: []),
              let match = regex.firstMatch(in: current, options: [], range: NSRange(location: 0, length: current.count)) {
            let nsCurrent = current as NSString
            let mod = nsCurrent.substring(with: match.range(at: 1))
            let inner = nsCurrent.substring(with: match.range(at: 2))
            modifiers.append(formatModifier(mod))
            current = inner
        }
        
        let baseKey = formatKey(current)
        
        if modifiers.isEmpty {
            return baseKey
        }
        
        return modifiers.joined(separator: "+") + "+" + baseKey
    }
    
    private static func formatModifier(_ mod: String) -> String {
        let modMap: [String: String] = [
            "LEFT_SHIFT": "⇧",
            "LSHIFT": "⇧",
            "LSHFT": "⇧",
            "LS": "⇧",
            "RIGHT_SHIFT": "⇧",
            "RSHIFT": "⇧",
            "RSHFT": "⇧",
            "RS": "⇧",
            "LEFT_CONTROL": "⌃",
            "LCTRL": "⌃",
            "LC": "⌃",
            "RIGHT_CONTROL": "⌃",
            "RCTRL": "⌃",
            "RC": "⌃",
            "LEFT_ALT": "⌥",
            "LALT": "⌥",
            "LA": "⌥",
            "RIGHT_ALT": "⌥",
            "RALT": "⌥",
            "RA": "⌥",
            "LEFT_GUI": "⌘",
            "LGUI": "⌘",
            "LG": "⌘",
            "RIGHT_GUI": "⌘",
            "RGUI": "⌘",
            "RG": "⌘",
            "LEFT_META": "◆",
            "LMETA": "◆",
            "RIGHT_META": "◆",
            "RMETA": "◆"
        ]
        
        return modMap[mod.uppercased()] ?? mod
    }
}

func loadKeymap(fromFile filePath: String) -> Keymap? {
    do {
        let data = try String(contentsOfFile: filePath, encoding: .utf8)
        return KeymapParser.parse(from: data)
    } catch {
        print("Error loading file: \(error)")
        return nil
    }
}