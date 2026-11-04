import Foundation

/// A change the app proposes for a file of the zmk-config. It is shown as
/// before and after, and only written once the user agrees.
struct ConfigEdit: Equatable {
    /// Relative to the zmk-config, e.g. "config/west.yml"
    let file: String
    let before: String
    let after: String
}

enum ConfigEditProposal: Equatable {
    case notNeeded
    case edit(ConfigEdit)
    /// Which build.yaml entry builds the central half is unclear: the user
    /// picks one of these
    case chooseCentral([String])
    /// The app doesn't understand the file well enough to change it safely
    case manual(String)
}

/// Works out the edits for the live layer and ZMK Studio, without a YAML
/// library: it only inserts lines and appends to values, and only in files
/// written in plain block style. Anything else (anchors, inline lists,
/// multi-line values, tabs) is left to the user. Every edit is checked
/// before it is offered: the file must read as set up afterwards, with
/// everything else unchanged.
enum FirmwareEdits {
    static let westFile = "config/west.yml"
    static let buildFile = "build.yaml"

    static let remotes: [(name: String, url: String)] = [
        ("zzeneg", "https://github.com/zzeneg"),
        ("srwi", "https://github.com/srwi"),
    ]
    static let projects: [(name: String, remote: String, revision: String)] = [
        ("zmk-raw-hid", "zzeneg", "main"),
        ("zmk-keypeek-layer-notifier", "srwi", "master"),
    ]
    static let studioSnippet = "studio-rpc-usb-uart"
    static let studioArg = "-DCONFIG_ZMK_STUDIO=y"

    // MARK: - west.yml

    static func addModules(toWest west: String) -> ConfigEditProposal {
        guard isPlain(west) else {
            return .manual("west.yml uses YAML the app doesn't edit (anchors, inline lists or multi-line values).")
        }
        let lines = west.components(separatedBy: "\n")
        guard let remoteList = list(named: "remotes", in: lines), let projectList = list(named: "projects", in: lines) else {
            return .manual("west.yml has no remotes: and projects: lists the app recognizes.")
        }

        // A remote that already points to the same GitHub account is reused
        var remoteNames: [String: String] = [:]
        var newRemotes: [(name: String, url: String)] = []
        for remote in remotes {
            if let existing = remoteList.items.first(where: { trimSlash(unquote($0["url-base"] ?? "")) == remote.url }),
               let name = existing["name"] {
                remoteNames[remote.name] = unquote(name)
            } else {
                if remoteList.items.contains(where: { unquote($0["name"] ?? "") == remote.name }) {
                    return .manual("west.yml already has a remote named \(remote.name) that points elsewhere.")
                }
                remoteNames[remote.name] = remote.name
                newRemotes.append(remote)
            }
        }
        let existingProjects = Set(projectList.items.compactMap { $0["name"].map(unquote) })
        let newProjects = projects.filter { !existingProjects.contains($0.name) }
        guard !newRemotes.isEmpty || !newProjects.isEmpty else { return .notNeeded }

        let remoteLines = newRemotes.flatMap { remote in [
            pad(remoteList.itemIndent) + "- name: \(remote.name)",
            pad(remoteList.keyIndent) + "url-base: \(remote.url)",
        ] }
        let projectLines = newProjects.flatMap { project in [
            pad(projectList.itemIndent) + "- name: \(project.name)",
            pad(projectList.keyIndent) + "remote: \(remoteNames[project.remote] ?? project.remote)",
            pad(projectList.keyIndent) + "revision: \(project.revision)",
        ] }

        // The later insertion first, so the earlier index stays right
        var result = lines
        var inserted: Set<Int> = []
        let insertions = [(remoteList.insertAt, remoteLines), (projectList.insertAt, projectLines)]
            .filter { !$0.1.isEmpty }
            .sorted { $0.0 > $1.0 }
        for (index, newLines) in insertions {
            result.insert(contentsOf: newLines, at: index)
            inserted = Set(inserted.map { $0 + newLines.count })
            inserted.formUnion(index..<(index + newLines.count))
        }
        let after = result.joined(separator: "\n")

        guard FirmwareSetup.check(west: after, build: "", keymaps: []).hasModules,
              removing(inserted, from: result) == lines else {
            return .manual("The app couldn't add the modules to west.yml safely.")
        }
        return .edit(ConfigEdit(file: westFile, before: west, after: after))
    }

    // MARK: - build.yaml

    /// Summaries of the include entries, as the user picks the central half
    static func buildEntrySummaries(_ build: String) -> [String] {
        let lines = build.components(separatedBy: "\n")
        return (list(named: "include", in: lines)?.items ?? []).map { item in
            [item["board"], item["shield"]].compactMap { $0.map(unquote) }.joined(separator: " · ")
        }
    }

    /// `central` is the index of the include entry the user picked
    static func enableRawHIDAndStudio(inBuild build: String, central: Int? = nil) -> ConfigEditProposal {
        guard isPlain(build) else {
            return .manual("build.yaml uses YAML the app doesn't edit (anchors, inline lists or multi-line values).")
        }
        let lines = build.components(separatedBy: "\n")
        guard let include = list(named: "include", in: lines), !include.items.isEmpty else {
            return .manual("build.yaml lists its boards without include: entries. Add the central half as an include entry yourself.")
        }

        let entries = include.items
        let index: Int
        if let central = central, entries.indices.contains(central) {
            index = central
        } else if let studio = singleIndex(entries, where: { ($0["snippet"] ?? "").contains("studio") }) {
            index = studio
        } else if entries.count == 1 {
            index = 0
        } else {
            return .chooseCentral(buildEntrySummaries(build))
        }
        let entry = entries[index]
        let range = include.itemRanges[index]

        var result = lines
        var addedLines: [String] = []
        var changedLines: Set<Int> = []

        // shield: the central half's shields plus raw_hid_adapter
        if let line = include.keyLines[index]["shield"] {
            if !unquote(entry["shield"] ?? "").split(separator: " ").contains("raw_hid_adapter") {
                result[line] = appending("raw_hid_adapter", toValueOf: result[line])
                changedLines.insert(line)
            }
        } else {
            addedLines.append(pad(include.keyIndent) + "shield: raw_hid_adapter")
        }

        // snippet: ZMK Studio over USB; another snippet is left to the user
        if let snippet = entry["snippet"].map(unquote) {
            if !snippet.contains("studio-rpc") {
                return .manual("The central half already uses the snippet \(snippet). Add \(studioSnippet) yourself.")
            }
        } else {
            addedLines.append(pad(include.keyIndent) + "snippet: \(studioSnippet)")
        }

        // cmake-args: Studio turned on
        if let line = include.keyLines[index]["cmake-args"] {
            let args = unquote(entry["cmake-args"] ?? "")
            if args.contains("CONFIG_ZMK_STUDIO=n") {
                return .manual("The central half turns ZMK Studio off in its cmake-args.")
            }
            if !args.contains("CONFIG_ZMK_STUDIO=y") {
                result[line] = appending(studioArg, toValueOf: result[line])
                changedLines.insert(line)
            }
        } else {
            addedLines.append(pad(include.keyIndent) + "cmake-args: \(studioArg)")
        }

        guard !addedLines.isEmpty || !changedLines.isEmpty else { return .notNeeded }
        result.insert(contentsOf: addedLines, at: range.upperBound)
        let inserted = Set(range.upperBound..<(range.upperBound + addedLines.count))
        let after = result.joined(separator: "\n")

        // Afterwards: same entries, this one set up, the others untouched
        let afterLines = after.components(separatedBy: "\n")
        guard let checked = list(named: "include", in: afterLines), checked.items.count == entries.count,
              zip(checked.items, entries).enumerated().allSatisfy({ $0.offset == index || $0.element.0 == $0.element.1 }),
              unquote(checked.items[index]["shield"] ?? "").split(separator: " ").contains("raw_hid_adapter"),
              (checked.items[index]["snippet"] ?? "").contains("studio-rpc"),
              (checked.items[index]["cmake-args"] ?? "").contains("CONFIG_ZMK_STUDIO=y"),
              checked.items[index].filter({ !["shield", "snippet", "cmake-args"].contains($0.key) })
                == entry.filter({ !["shield", "snippet", "cmake-args"].contains($0.key) }),
              removing(inserted, from: afterLines).enumerated().allSatisfy({ changedLines.contains($0.offset) || $0.element == lines[$0.offset] }) else {
            return .manual("The app couldn't change build.yaml safely.")
        }
        return .edit(ConfigEdit(file: buildFile, before: build, after: after))
    }

    // MARK: - Writing

    enum ApplyError: Error, Equatable {
        /// The file changed since the edit was worked out
        case fileChanged
    }

    static func apply(_ edit: ConfigEdit, in root: URL) throws {
        let url = root.appendingPathComponent(edit.file)
        let current = try String(contentsOf: url, encoding: .utf8)
        guard current == edit.before else { throw ApplyError.fileChanged }
        try edit.after.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Plain block YAML

    /// A block list like `remotes:` with its items
    struct BlockList {
        var items: [[String: String]] = []
        /// Line ranges of the items, up to their last content line
        var itemRanges: [Range<Int>] = []
        /// Per item, the line of each key
        var keyLines: [[String: Int]] = []
        var itemIndent = 2
        var keyIndent = 4
        /// After the last item's last content line
        var insertAt = 0
    }

    static func list(named name: String, in lines: [String]) -> BlockList? {
        guard let keyLine = lines.firstIndex(where: { code($0).trimmingCharacters(in: .whitespaces) == "\(name):" }) else {
            return nil
        }
        let keyIndent = indent(of: lines[keyLine])
        var block = BlockList()
        block.itemIndent = keyIndent + 2
        block.keyIndent = keyIndent + 4
        block.insertAt = keyLine + 1
        var itemIndent: Int?

        var index = keyLine + 1
        while index < lines.count {
            let line = lines[index]
            let trimmed = code(line).trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                index += 1
                continue
            }
            let lineIndent = indent(of: line)
            // The list ends at the next key at or above its own level
            let isItem = trimmed.hasPrefix("- ") || trimmed == "-"
            if lineIndent < keyIndent || (lineIndent == keyIndent && !isItem) {
                break
            }
            if isItem && (itemIndent == nil || lineIndent == itemIndent) {
                itemIndent = lineIndent
                block.itemIndent = lineIndent
                block.items.append([:])
                block.keyLines.append([:])
                block.itemRanges.append(index..<(index + 1))
                let rest = String(trimmed.dropFirst(2))
                block.keyIndent = lineIndent + 2 + (rest.count - rest.drop(while: { $0 == " " }).count)
                addPair(rest, line: index, to: &block)
            } else if !block.items.isEmpty {
                addPair(trimmed, line: index, to: &block)
            }
            if !block.items.isEmpty {
                let last = block.itemRanges.count - 1
                block.itemRanges[last] = block.itemRanges[last].lowerBound..<(index + 1)
            }
            block.insertAt = index + 1
            index += 1
        }
        return block
    }

    private static func addPair(_ text: String, line: Int, to block: inout BlockList) {
        guard let colon = text.range(of: ":") else { return }
        let key = text[..<colon.lowerBound].trimmingCharacters(in: .whitespaces)
        let value = text[colon.upperBound...].trimmingCharacters(in: .whitespaces)
        let last = block.items.count - 1
        block.items[last][key] = value
        block.keyLines[last][key] = line
    }

    /// Block style only: no tabs, anchors, aliases, merge keys, inline
    /// collections or multi-line values
    static func isPlain(_ yaml: String) -> Bool {
        for line in yaml.components(separatedBy: "\n") {
            let text = code(line)
            if text.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            if text.prefix(while: { $0 == " " || $0 == "\t" }).contains("\t") { return false }
            var trimmed = text.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- ") { trimmed = String(trimmed.dropFirst(2)) }
            if trimmed.hasPrefix("<<") { return false }
            if let first = trimmed.first, "&*|>{[".contains(first) { return false }
            let value = trimmed.range(of: ": ").map { String(trimmed[$0.upperBound...]) }
                ?? (trimmed.hasSuffix(":") ? "" : trimmed)
            let start = value.trimmingCharacters(in: .whitespaces).first
            if let start = start, "&*|>{[".contains(start) { return false }
        }
        return true
    }

    // MARK: - Lines

    /// The line without its comment
    private static func code(_ line: String) -> String {
        var inQuote: Character?
        for (offset, char) in line.enumerated() {
            if let quote = inQuote {
                if char == quote { inQuote = nil }
            } else if char == "\"" || char == "'" {
                inQuote = char
            } else if char == "#", offset == 0 || line[line.index(line.startIndex, offsetBy: offset - 1)] == " " {
                return String(line.prefix(offset))
            }
        }
        return line
    }

    /// `shield: corne_left # main` → `shield: corne_left raw_hid_adapter # main`,
    /// inside quotes when the value is quoted
    static func appending(_ token: String, toValueOf line: String) -> String {
        let codePart = code(line)
        let comment = String(line.dropFirst(codePart.count))
        let trimmedCode = codePart.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
        let trailing = String(codePart.dropFirst(trimmedCode.count))
        if let last = trimmedCode.last, last == "\"" || last == "'" {
            return String(trimmedCode.dropLast()) + " \(token)" + String(last) + trailing + comment
        }
        return trimmedCode + " \(token)" + trailing + comment
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2, let first = value.first, first == value.last, first == "\"" || first == "'" else {
            return value
        }
        return String(value.dropFirst().dropLast())
    }

    private static func trimSlash(_ url: String) -> String {
        url.hasSuffix("/") ? String(url.dropLast()) : url
    }

    private static func indent(of line: String) -> Int {
        line.prefix(while: { $0 == " " }).count
    }

    private static func pad(_ count: Int) -> String {
        String(repeating: " ", count: count)
    }

    private static func singleIndex(_ entries: [[String: String]], where matches: ([String: String]) -> Bool) -> Int? {
        let found = entries.indices.filter { matches(entries[$0]) }
        return found.count == 1 ? found[0] : nil
    }

    /// The lines without the inserted ones, which must give the original
    private static func removing(_ inserted: Set<Int>, from lines: [String]) -> [String] {
        lines.enumerated().filter { !inserted.contains($0.offset) }.map(\.element)
    }
}

/// The part of a file an edit touches, as it is now and as it will be
struct EditExcerpt: Equatable {
    struct Line: Equatable {
        /// 1-based, as editors count
        let number: Int
        let text: String
        /// Removed (before) or added (after) by the edit
        let changed: Bool
    }

    let before: [Line]
    let after: [Line]

    /// One excerpt per changed region, with `context` unchanged lines around it
    static func excerpts(of edit: ConfigEdit, context: Int = 2) -> [EditExcerpt] {
        let old = edit.before.components(separatedBy: "\n")
        let new = edit.after.components(separatedBy: "\n")
        let ops = lineDiff(old, new)
        let changedOps = ops.indices.filter { ops[$0].kind != .same }
        guard !changedOps.isEmpty else { return [] }

        // Windows around the changes, merged where they touch
        var windows: [ClosedRange<Int>] = []
        for index in changedOps {
            let window = max(0, index - context)...min(ops.count - 1, index + context)
            if let last = windows.last, window.lowerBound <= last.upperBound + 1 {
                windows[windows.count - 1] = last.lowerBound...max(last.upperBound, window.upperBound)
            } else {
                windows.append(window)
            }
        }
        return windows.map { window in
            var before: [Line] = []
            var after: [Line] = []
            for op in ops[window] {
                if let oldIndex = op.oldIndex {
                    before.append(Line(number: oldIndex + 1, text: old[oldIndex], changed: op.kind == .removed))
                }
                if let newIndex = op.newIndex {
                    after.append(Line(number: newIndex + 1, text: new[newIndex], changed: op.kind == .added))
                }
            }
            return EditExcerpt(before: before, after: after)
        }
    }

    private struct Op {
        enum Kind { case same, removed, added }
        let kind: Kind
        let oldIndex: Int?
        let newIndex: Int?
    }

    /// Longest common subsequence of lines; config files are short
    private static func lineDiff(_ old: [String], _ new: [String]) -> [Op] {
        var lengths = Array(repeating: Array(repeating: 0, count: new.count + 1), count: old.count + 1)
        for i in stride(from: old.count - 1, through: 0, by: -1) {
            for j in stride(from: new.count - 1, through: 0, by: -1) {
                lengths[i][j] = old[i] == new[j] ? lengths[i + 1][j + 1] + 1 : max(lengths[i + 1][j], lengths[i][j + 1])
            }
        }
        var ops: [Op] = []
        var i = 0
        var j = 0
        while i < old.count || j < new.count {
            if i < old.count, j < new.count, old[i] == new[j] {
                ops.append(Op(kind: .same, oldIndex: i, newIndex: j))
                i += 1
                j += 1
            } else if j < new.count, i == old.count || lengths[i][j + 1] >= lengths[i + 1][j] {
                ops.append(Op(kind: .added, oldIndex: nil, newIndex: j))
                j += 1
            } else {
                ops.append(Op(kind: .removed, oldIndex: i, newIndex: nil))
                i += 1
            }
        }
        return ops
    }
}
