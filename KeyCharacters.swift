import Carbon
import Foundation

/// The character a key types in the active macOS keyboard layout: ⌥⇧2 is €
/// in the ABC layout, the SEMI key is Ö in the German one. Keys with ⌃ or ⌘
/// are shortcuts and type nothing.
///
/// macOS only hands out the layout on the main thread, while keymaps are
/// parsed in the background, so the characters are worked out up front.
enum KeyCharacters {
    struct Combo: Hashable {
        let keyCode: UInt16
        let shift: Bool
        let option: Bool
    }

    private static let lock = NSLock()
    private static var storedTable: [Combo: String] = [:]

    /// Empty until the app loads the system layout, so tests don't depend on
    /// the machine's layout
    static var table: [Combo: String] {
        get { lock.lock(); defer { lock.unlock() }; return storedTable }
        set { lock.lock(); storedTable = newValue; lock.unlock() }
    }

    /// The typed character for a ZMK key expression like "LS(LA(N2))", or nil
    /// for keys that type nothing (shortcuts, modifiers, arrows, …)
    static func typedCharacter(for expression: String) -> String? {
        var shift = false
        var option = false
        var key = expression.uppercased()
        while key.hasSuffix(")"), let open = key.firstIndex(of: "(") {
            switch key[..<open] {
            case "LS", "RS": shift = true
            case "LA", "RA": option = true
            default: return nil
            }
            key = String(key[key.index(after: open)..<key.index(before: key.endIndex)])
        }
        guard let (keyCode, impliedShift) = keyCodes[key],
              let typed = table[Combo(keyCode: keyCode, shift: shift || impliedShift, option: option)],
              typed.unicodeScalars.count == 1, let scalar = typed.unicodeScalars.first,
              !CharacterSet.controlCharacters.contains(scalar), !CharacterSet.whitespaces.contains(scalar) else {
            return nil
        }
        // Plain letters as printed on keycaps: Q, Ö. Not ß → SS.
        let upper = typed.uppercased()
        return !shift && !option && !impliedShift && upper.count == 1 ? upper : typed
    }

    /// Works out every combo of the keys below in the active layout
    static func loadSystemLayout() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            table = [:]
            return
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var characters: [Combo: String] = [:]
        layoutData.withUnsafeBytes { buffer in
            guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return }
            for keyCode in Set(keyCodes.values.map(\.0)) {
                for shift in [false, true] {
                    for option in [false, true] {
                        var modifiers: UInt32 = 0
                        if shift { modifiers |= UInt32(shiftKey >> 8) }
                        if option { modifiers |= UInt32(optionKey >> 8) }
                        var deadKeyState: UInt32 = 0
                        var length = 0
                        var chars = [UniChar](repeating: 0, count: 4)
                        // A dead key (⌥U) shows its own mark: ¨
                        let status = UCKeyTranslate(
                            layout, keyCode, UInt16(kUCKeyActionDisplay), modifiers, UInt32(LMGetKbdType()),
                            OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeyState, chars.count, &length, &chars
                        )
                        if status == noErr, length > 0 {
                            characters[Combo(keyCode: keyCode, shift: shift, option: option)] = String(utf16CodeUnits: chars, count: length)
                        }
                    }
                }
            }
        }
        table = characters
    }

    /// ZMK key names of the typing keys: macOS virtual key code, and whether
    /// the name implies shift (EXCL is LS(N1))
    private static let keyCodes: [String: (UInt16, Bool)] = {
        var codes: [String: (UInt16, Bool)] = [:]
        let letters: [(String, UInt16)] = [
            ("A", 0x00), ("S", 0x01), ("D", 0x02), ("F", 0x03), ("H", 0x04), ("G", 0x05), ("Z", 0x06),
            ("X", 0x07), ("C", 0x08), ("V", 0x09), ("B", 0x0B), ("Q", 0x0C), ("W", 0x0D), ("E", 0x0E),
            ("R", 0x0F), ("Y", 0x10), ("T", 0x11), ("O", 0x1F), ("U", 0x20), ("I", 0x22), ("P", 0x23),
            ("L", 0x25), ("J", 0x26), ("K", 0x28), ("N", 0x2D), ("M", 0x2E),
        ]
        for (name, code) in letters {
            codes[name] = (code, false)
        }
        let digits: [UInt16] = [0x1D, 0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C, 0x19]
        for (digit, code) in digits.enumerated() {
            codes["N\(digit)"] = (code, false)
            codes["NUMBER_\(digit)"] = (code, false)
        }
        let punctuation: [([String], UInt16)] = [
            (["MINUS"], 0x1B), (["EQUAL"], 0x18), (["LBKT", "LEFT_BRACKET"], 0x21),
            (["RBKT", "RIGHT_BRACKET"], 0x1E), (["BSLH", "BACKSLASH", "NUHS", "NON_US_HASH"], 0x2A),
            (["SEMI", "SEMICOLON"], 0x29), (["SQT", "SINGLE_QUOTE", "APOSTROPHE", "APOS"], 0x27),
            (["GRAVE"], 0x32), (["COMMA"], 0x2B), (["DOT", "PERIOD"], 0x2F), (["FSLH", "SLASH"], 0x2C),
            (["NUBS", "NON_US_BACKSLASH"], 0x0A),
        ]
        for (names, code) in punctuation {
            for name in names {
                codes[name] = (code, false)
            }
        }
        let shifted: [([String], UInt16)] = [
            (["EXCL", "EXCLAMATION"], 0x12), (["AT", "AT_SIGN"], 0x13), (["HASH", "POUND"], 0x14),
            (["DLLR", "DOLLAR"], 0x15), (["PRCNT", "PERCENT"], 0x17), (["CARET"], 0x16),
            (["AMPS", "AMPERSAND"], 0x1A), (["STAR", "ASTRK", "ASTERISK"], 0x1C),
            (["LPAR", "LEFT_PARENTHESIS"], 0x19), (["RPAR", "RIGHT_PARENTHESIS"], 0x1D),
            (["UNDER", "UNDERSCORE"], 0x1B), (["PLUS"], 0x18), (["LBRC", "LEFT_BRACE"], 0x21),
            (["RBRC", "RIGHT_BRACE"], 0x1E), (["PIPE"], 0x2A), (["COLON"], 0x29),
            (["DQT", "DOUBLE_QUOTES"], 0x27), (["TILDE"], 0x32), (["LT", "LESS_THAN"], 0x2B),
            (["GT", "GREATER_THAN"], 0x2F), (["QMARK", "QUESTION"], 0x2C),
        ]
        for (names, code) in shifted {
            for name in names {
                codes[name] = (code, true)
            }
        }
        return codes
    }()
}
