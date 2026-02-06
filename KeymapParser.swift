import Foundation

/// Represents a single key binding with both display text and raw code
struct KeyBinding: Identifiable, Equatable {
    let id = UUID()
    let displayText: String   // Human-readable display (e.g., "Q", "CTRL+Q")
    let rawCode: String       // Original keymap code (e.g., "&long_MT RIGHT_CONTROL Q")
    let alias: String?        // User-defined alias from // =alias comment
    let row: Int
    let column: Int
    
    /// Returns alias if present, otherwise displayText
    var effectiveDisplayText: String {
        alias ?? displayText
    }
    
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
    let name: String          // e.g., "Sweep", "Corne", "Go60", "Custom (60 keys)"
    let isSplit: Bool         // Whether the keyboard has a split layout (gap in the middle)
    
    /// Create a layout directly from parsed data - the generalized approach
    static func create(
        keyCount: Int,
        keysPerRow: [Int],
        detectedName: String?,
        isSplit: Bool = true   // Default to split since most ZMK boards are split
    ) -> KeyboardLayout {
        let rowCount = keysPerRow.count
        let thumbKeys = keysPerRow.last ?? 0
        let firstRowKeys = keysPerRow.first ?? 0
        
        // Thumb cluster detection: last row has fewer keys than first row
        let hasThumbCluster = thumbKeys < firstRowKeys
        
        // Use detected name or generate a descriptive one
        let name = detectedName ?? "Custom (\(keyCount) keys)"
        
        return KeyboardLayout(
            totalKeys: keyCount,
            keysPerRow: keysPerRow,
            rowCount: rowCount,
            hasThumbCluster: hasThumbCluster,
            thumbKeysCount: hasThumbCluster ? thumbKeys : 0,
            name: name,
            isSplit: isSplit
        )
    }
    
    /// Known keyboard configurations: name -> isSplit
    private static let knownKeyboards: [String: (name: String, isSplit: Bool)] = [
        // Split keyboards
        "sweep": ("Sweep/Cradio", true),
        "cradio": ("Sweep/Cradio", true),
        "corne": ("Corne", true),
        "crkbd": ("Corne", true),
        "sofle": ("Sofle", true),
        "lily58": ("Lily58", true),
        "kyria": ("Kyria", true),
        "ferris": ("Ferris", true),
        "ergodox": ("Ergodox", true),
        "dactyl": ("Dactyl", true),
        "totem": ("Totem", true),
        "go60": ("Go60", true),
        "glove80": ("Glove80", true),
        // Non-split keyboards
        "planck": ("Planck", false),
        "preonic": ("Preonic", false),
        "reviung": ("Reviung", false),
        "reviung41": ("Reviung41", false),
        "bdn9": ("BDN9", false),
        "nibble": ("Nibble", false),
    ]
    
    /// Detect keyboard info from file content (comments, defines, filename, etc.)
    /// Returns (name, isSplit) or nil if not detected
    static func detectKeyboardInfo(from content: String, filePath: String? = nil) -> (name: String, isSplit: Bool)? {
        // Check for Go60/Glove80 Layout Editor signature first
        if content.contains("GO60 LAYOUT EDITOR") || content.contains("KB_TYPE_GO_60") {
            return ("Go60", true)
        }
        if content.contains("GLOVE80 LAYOUT EDITOR") || content.contains("KB_TYPE_GLOVE_80") {
            return ("Glove80", true)
        }
        
        let lowercased = content.lowercased()
        let filePathLower = filePath?.lowercased() ?? ""
        
        for (keyword, info) in knownKeyboards {
            // Check in filename first (most reliable)
            if filePathLower.contains(keyword) {
                return info
            }
            
            // Check in content - look for the keyword anywhere
            if lowercased.contains(keyword) {
                return info
            }
        }
        
        return nil
    }
    
    /// Detect keyboard name from file content (legacy method for compatibility)
    static func detectName(from content: String) -> String? {
        return detectKeyboardInfo(from: content)?.name
    }
}

/// Complete parsed keymap with all layers and layout info
struct Keymap {
    var layers: [KeymapLayer]
    var layout: KeyboardLayout
    var behaviors: [String: String]  // behavior name -> description
    var macros: [String: String]     // macro name -> description
    
    /// Default layout for empty/uninitialized state
    private static let defaultLayout = KeyboardLayout(
        totalKeys: 0,
        keysPerRow: [],
        rowCount: 0,
        hasThumbCluster: false,
        thumbKeysCount: 0,
        name: "Unknown",
        isSplit: true
    )
    
    init(layers: [KeymapLayer] = [], layout: KeyboardLayout? = nil, behaviors: [String: String] = [:], macros: [String: String] = [:]) {
        self.layers = layers
        self.layout = layout ?? Keymap.defaultLayout
        self.behaviors = behaviors
        self.macros = macros
    }
}

class KeymapParser {
    
    /// Parse a ZMK keymap file and return a complete Keymap structure
    static func parse(from data: String, filePath: String? = nil) -> Keymap? {
        // Detect keyboard info from raw content BEFORE removing comments
        let keyboardInfo = KeyboardLayout.detectKeyboardInfo(from: data, filePath: filePath)
        let detectedName = keyboardInfo?.name
        
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
        
        var keymapContent = String(cleanedData[keymapRange])
        
        // Strip the outer "keymap { ... }" to avoid matching "keymap" as a layer
        if let firstBrace = keymapContent.firstIndex(of: "{"),
           let lastBrace = keymapContent.lastIndex(of: "}") {
            let start = keymapContent.index(after: firstBrace)
            let end = lastBrace
            if start < end {
                keymapContent = String(keymapContent[start..<end])
            }
        }
        
        // Parse each layer
        layers = parseLayers(from: keymapContent)
        
        // If no layers found, return nil
        if layers.isEmpty {
            return nil
        }
        
        // Detect if keyboard is split:
        // 1. Use known keyboard info if available (most reliable)
        // 2. Fall back to spacing pattern analysis
        let isSplit: Bool
        if let knownSplit = keyboardInfo?.isSplit {
            isSplit = knownSplit
        } else {
            isSplit = detectSplitLayout(from: keymapContent)
        }
        
        // Create layout from actual parsed structure (generalized approach)
        let firstLayer = layers[0]
        let keysPerRow = calculateKeysPerRow(bindings: firstLayer.bindings)
        let layout = KeyboardLayout.create(
            keyCount: firstLayer.bindings.count,
            keysPerRow: keysPerRow,
            detectedName: detectedName,
            isSplit: isSplit
        )
        print("[KeymapParser] Detected: \(layout.name) with \(layers.count) layers, \(firstLayer.bindings.count) keys, rows: \(keysPerRow), split: \(isSplit)")
        
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
                // Check if this is an alias comment /* =... */ - preserve it!
                let commentStart = i
                var commentEnd = data.index(after: nextI)
                var commentContent = ""
                
                // Find the end of the comment and extract content
                while commentEnd < data.index(data.endIndex, offsetBy: -1) {
                    if data[commentEnd] == "*" && data[data.index(after: commentEnd)] == "/" {
                        commentEnd = data.index(after: data.index(after: commentEnd))
                        break
                    }
                    commentContent.append(data[commentEnd])
                    commentEnd = data.index(after: commentEnd)
                }
                
                // Check if it's an alias comment (starts with = after trimming whitespace)
                let trimmedContent = commentContent.trimmingCharacters(in: .whitespaces)
                if trimmedContent.hasPrefix("=") {
                    // Preserve alias comment - append the whole thing
                    for idx in data.indices[commentStart..<commentEnd] {
                        result.append(data[idx])
                    }
                    i = commentEnd
                } else {
                    // Regular block comment - skip it but preserve newlines
                    i = data.index(after: nextI)
                    while i < data.index(data.endIndex, offsetBy: -1) {
                        if data[i] == "*" && data[data.index(after: i)] == "/" {
                            i = data.index(after: data.index(after: i))
                            break
                        }
                        if data[i] == "\n" {
                            result.append("\n")
                        }
                        i = data.index(after: i)
                    }
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
        
        // Match layer definition block
        // Group 1: Layer ID (e.g. default_layer)
        // Group 2: Content before bindings (where label might be)
        // Group 3: Bindings content
        let layerPattern = "(\\w+)\\s*\\{([^}]*?)bindings\\s*=\\s*<(.*?)>\\s*;"
        guard let regex = try? NSRegularExpression(pattern: layerPattern, options: [.dotMatchesLineSeparators]) else {
            return layers
        }
        
        let nsContent = keymapContent as NSString
        let matches = regex.matches(in: keymapContent, options: [], range: NSRange(location: 0, length: nsContent.length))
        
        for match in matches {
            guard match.numberOfRanges >= 4 else { continue }
            
            let layerId = nsContent.substring(with: match.range(at: 1))
            let preBindingsContent = nsContent.substring(with: match.range(at: 2))
            let bindingsRaw = nsContent.substring(with: match.range(at: 3))
            
            // Try to find label in pre-bindings content
            var layerName = layerId
            let labelPattern = "(?:label|display-name)\\s*=\\s*\"([^\"]*)\""
            if let labelRegex = try? NSRegularExpression(pattern: labelPattern, options: []),
               let labelMatch = labelRegex.firstMatch(in: preBindingsContent, options: [], range: NSRange(location: 0, length: preBindingsContent.count)) {
                layerName = (preBindingsContent as NSString).substring(with: labelMatch.range(at: 1))
            }
            
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
    
    /// Strip C-style line comments (// ...) from a line, preserving block comments
    private static func stripLineComment(_ line: String) -> String {
        if let commentRange = line.range(of: "//") {
            return String(line[..<commentRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        return line
    }
    
    /// Extract inline alias from block comment: /* =alias */
    /// Returns the alias text or nil if not found
    private static func extractInlineAlias(from token: String) -> (binding: String, alias: String?)? {
        // Look for pattern: &binding /* =alias */
        let pattern = #"^(.+?)\s*/\*\s*=\s*(.+?)\s*\*/"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        
        let nsToken = token as NSString
        guard let match = regex.firstMatch(in: token, options: [], range: NSRange(location: 0, length: nsToken.length)),
              match.numberOfRanges >= 3 else {
            return nil
        }
        
        let binding = nsToken.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
        let alias = nsToken.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
        
        return (binding, alias.isEmpty ? nil : alias)
    }
    
    /// Parse the raw bindings content of a layer
    static func parseBindings(from bindingsRaw: String) -> [KeyBinding] {
        var bindings: [KeyBinding] = []
        
        // Split by newlines first to preserve row structure
        let originalLines = bindingsRaw.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        
        var currentRow = 0
        
        for originalLine in originalLines {
            // Strip line comment but keep block comments for inline alias parsing
            let strippedLine = stripLineComment(originalLine)
            guard !strippedLine.isEmpty else { continue }
            
            // Tokenize - this will include any /* =alias */ attached to bindings
            let tokens = tokenizeBindingsWithAliases(strippedLine)
            
            // If this line has bindings, add them to the current row
            if !tokens.isEmpty {
                for (_, token) in tokens.enumerated() {
                    var rawCode = token
                    var alias: String? = nil
                    
                    // Check for inline alias: &binding /* =alias */
                    if let extracted = extractInlineAlias(from: token) {
                        rawCode = extracted.binding
                        alias = extracted.alias
                    }
                    
                    let displayText = parseDisplayText(from: rawCode)
                    
                    let binding = KeyBinding(
                        displayText: displayText,
                        rawCode: rawCode,
                        alias: alias,
                        row: currentRow,
                        column: bindings.filter { $0.row == currentRow }.count
                    )
                    bindings.append(binding)
                }
                currentRow += 1
            }
        }
        
        return bindings
    }
    
    /// Tokenize bindings, keeping /* =alias */ attached to their bindings
    private static func tokenizeBindingsWithAliases(_ input: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var parenDepth = 0
        var inBlockComment = false
        
        let chars = Array(input)
        var i = 0
        
        while i < chars.count {
            let char = chars[i]
            
            // Track block comments /* ... */
            if !inBlockComment && i + 1 < chars.count && char == "/" && chars[i + 1] == "*" {
                inBlockComment = true
                current.append(char)
                i += 1
                continue
            }
            if inBlockComment && i + 1 < chars.count && char == "*" && chars[i + 1] == "/" {
                inBlockComment = false
                current.append(char)
                current.append(chars[i + 1])
                i += 2
                continue
            }
            
            if inBlockComment {
                current.append(char)
                i += 1
                continue
            }
            
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
                // Space outside parentheses - check if next non-space is & or /*
                var nextNonSpace = i + 1
                while nextNonSpace < chars.count && chars[nextNonSpace] == " " {
                    nextNonSpace += 1
                }
                // Check for /* (block comment that might be an alias)
                let nextIsBlockComment = nextNonSpace + 1 < chars.count && 
                    chars[nextNonSpace] == "/" && chars[nextNonSpace + 1] == "*"
                
                if nextNonSpace < chars.count && chars[nextNonSpace] == "&" {
                    // End of current token, next is a new binding
                    if !current.trimmingCharacters(in: .whitespaces).isEmpty {
                        tokens.append(current.trimmingCharacters(in: .whitespaces))
                    }
                    current = ""
                } else if nextIsBlockComment {
                    // Keep block comment attached to current token
                    current.append(char)
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
    
    /// Detect if the keyboard is a split layout by analyzing spacing patterns
    /// Split keyboards have a large gap at the MIDDLE of each row (symmetric split)
    /// Non-split keyboards have gaps distributed throughout for alignment, not concentrated in the middle
    private static func detectSplitLayout(from keymapContent: String) -> Bool {
        // Find bindings content
        let bindingsPattern = "bindings\\s*=\\s*<(.*?)>"
        guard let regex = try? NSRegularExpression(pattern: bindingsPattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: keymapContent, options: [], range: NSRange(location: 0, length: (keymapContent as NSString).length)),
              match.numberOfRanges >= 2 else {
            return true // Default to split for most ZMK keyboards
        }
        
        let bindingsRaw = (keymapContent as NSString).substring(with: match.range(at: 1))
        
        // Analyze each line for spacing patterns
        let lines = bindingsRaw.components(separatedBy: "\n")
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !trimmed.isEmpty && trimmed.contains("&")
            }
        
        guard !lines.isEmpty else { return true }
        
        var linesWithMiddleGap = 0
        var totalBindingLines = 0
        
        for line in lines {
            // Count bindings in this line by counting &
            let bindingCount = line.components(separatedBy: "&").count - 1
            if bindingCount < 6 { continue } // Skip short lines - need enough keys to detect pattern
            
            totalBindingLines += 1
            
            // Find positions of all bindings (where & appears)
            var bindingPositions: [Int] = []
            for (index, char) in line.enumerated() {
                if char == "&" {
                    bindingPositions.append(index)
                }
            }
            
            guard bindingPositions.count >= 6 else { continue }
            
            // The middle gap should be between binding (count/2 - 1) and (count/2)
            // For 12 keys: gap between key 5 and 6 (indices 5 and 6 in bindingPositions)
            let middleIndex = bindingPositions.count / 2
            guard middleIndex > 0 && middleIndex < bindingPositions.count else { continue }
            
            // Calculate gap at the middle
            let leftMiddlePos = bindingPositions[middleIndex - 1]
            let rightMiddlePos = bindingPositions[middleIndex]
            
            // Find where the left binding ends (next & or end of content before next &)
            let leftBindingEnd = rightMiddlePos // The gap is from after left binding to start of right binding
            
            // Extract the substring between these two bindings
            let startIdx = line.index(line.startIndex, offsetBy: leftMiddlePos)
            let endIdx = line.index(line.startIndex, offsetBy: rightMiddlePos)
            let segment = String(line[startIdx..<endIdx])
            
            // Count trailing spaces in this segment (after the binding text)
            // The binding is like "&kp X" - we want the spaces after the X
            if let lastSpace = segment.lastIndex(of: " ") {
                let spacesAtEnd = segment.suffix(from: lastSpace).filter { $0 == " " || $0 == "\t" }.count
                
                // Also calculate average gap between other bindings for comparison
                var otherGaps: [Int] = []
                for i in 1..<bindingPositions.count {
                    if i == middleIndex { continue } // Skip the middle gap
                    let prevPos = bindingPositions[i - 1]
                    let currPos = bindingPositions[i]
                    let gap = currPos - prevPos
                    otherGaps.append(gap)
                }
                
                let middleGap = rightMiddlePos - leftMiddlePos
                let avgOtherGap = otherGaps.isEmpty ? 0 : otherGaps.reduce(0, +) / otherGaps.count
                
                // Split keyboard: middle gap is significantly larger than average gap
                // Using 1.5x as threshold since split keyboards have a noticeable visual gap
                if avgOtherGap > 0 && middleGap > avgOtherGap + avgOtherGap / 2 {
                    linesWithMiddleGap += 1
                }
            }
        }
        
        // If most lines have a larger-than-average gap at the middle, it's a split keyboard
        if totalBindingLines > 0 {
            let splitRatio = Double(linesWithMiddleGap) / Double(totalBindingLines)
            return splitRatio > 0.5
        }
        
        return true // Default to split
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
            "LEFT_BRACKET": "[",
            "RBKT": "]",
            "RIGHT_BRACKET": "]",
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
