import Foundation

/// What a zmk-config needs for the live layer and reading the keymap, and
/// which of it is already there. Reads the files only, never writes them.
struct FirmwareSetup: Equatable {
    /// config/west.yml lists zmk-raw-hid and zmk-keypeek-layer-notifier
    var hasModules = false
    /// build.yaml builds the central half with the raw_hid_adapter shield
    var hasRawHID = false
    /// build.yaml builds the central half with ZMK Studio
    var hasStudio = false
    /// A keymap has &studio_unlock on some key
    var hasUnlockKey = false

    /// From build.yaml, for examples that fit this keyboard
    var board = "nice_nano_v2"
    var centralShield = "<keyboard>_left"
    /// config/<keyboard>.keymap
    var keymapFile = "config/<keyboard>.keymap"

    var filesAreReady: Bool { hasModules && hasRawHID && hasStudio && hasUnlockKey }

    /// The folder with build.yaml, also when its config folder was chosen
    static func configRoot(for folder: URL) -> URL {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: folder.appendingPathComponent("build.yaml").path),
           folder.lastPathComponent == "config",
           fileManager.fileExists(atPath: folder.deletingLastPathComponent().appendingPathComponent("build.yaml").path) {
            return folder.deletingLastPathComponent()
        }
        return folder
    }

    static func check(_ folder: URL) -> FirmwareSetup {
        let root = configRoot(for: folder)
        let config = root.appendingPathComponent("config")
        let keymaps = ((try? FileManager.default.contentsOfDirectory(atPath: config.path)) ?? [])
            .filter { $0.hasSuffix(".keymap") }
            .sorted()
            .map { (name: $0, content: read(config.appendingPathComponent($0))) }
        return check(
            west: read(config.appendingPathComponent("west.yml")),
            build: read(root.appendingPathComponent("build.yaml")),
            keymaps: keymaps
        )
    }

    static func check(west: String, build: String, keymaps: [(name: String, content: String)]) -> FirmwareSetup {
        var setup = FirmwareSetup()
        let westProjects = Set(yamlValues(of: "name", in: west))
        setup.hasModules = westProjects.contains("zmk-raw-hid") && westProjects.contains("zmk-keypeek-layer-notifier")

        // The central half: the entry with Studio, else the left half
        let entries = buildEntries(in: build)
        let central = entries.first { ($0["snippet"] ?? "").contains("studio") }
            ?? entries.first { ($0["shield"] ?? "").contains("left") }
        if let central = central {
            let shields = (central["shield"] ?? "").split(separator: " ").map(String.init)
            setup.hasRawHID = shields.contains("raw_hid_adapter")
            setup.hasStudio = (central["snippet"] ?? "").contains("studio-rpc")
                && (central["cmake-args"] ?? "").contains("CONFIG_ZMK_STUDIO=y")
            if let shield = shields.first(where: { $0 != "raw_hid_adapter" }) {
                setup.centralShield = shield
            }
            if let board = central["board"] {
                setup.board = board
            }
        }

        if let keymap = keymaps.first {
            setup.keymapFile = "config/\(keymap.name)"
        }
        setup.hasUnlockKey = keymaps.contains { keymap in
            keymap.content.split(separator: "\n").contains { line in
                let code = line.components(separatedBy: "//")[0]
                return code.contains("&studio_unlock")
            }
        }
        return setup
    }

    // MARK: - Reading YAML lines

    private static func read(_ url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    /// Lines without comments, which commented-out entries are made of
    private static func codeLines(_ yaml: String) -> [String] {
        yaml.split(separator: "\n").compactMap { line in
            let code = line.components(separatedBy: "#")[0]
            return code.trimmingCharacters(in: .whitespaces).isEmpty ? nil : code
        }
    }

    private static func yamlValues(of key: String, in yaml: String) -> [String] {
        codeLines(yaml).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let entry = trimmed.hasPrefix("- ") ? String(trimmed.dropFirst(2)) : trimmed
            guard entry.hasPrefix("\(key):") else { return nil }
            return entry.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces)
        }
    }

    /// The board/shield entries of build.yaml, as key-value pairs
    private static func buildEntries(in yaml: String) -> [[String: String]] {
        var entries: [[String: String]] = []
        for line in codeLines(yaml) {
            var trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- ") {
                entries.append([:])
                trimmed = String(trimmed.dropFirst(2))
            }
            guard !entries.isEmpty, let colon = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[..<colon])
            let value = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            entries[entries.count - 1][key] = value
        }
        return entries
    }
}
