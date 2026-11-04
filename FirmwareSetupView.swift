import SwiftUI

/// Walks through the firmware changes in the user's zmk-config, as a page
/// of the setup window, which stays open next to the editor. The app checks the files
/// every two seconds and ticks off what's done. Changes to west.yml and
/// build.yaml are shown as now and after, and only written when the user
/// agrees; the unlock key, building and flashing are the user's steps.
struct FirmwareSetupView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var viewModel: KeymapViewModel
    let onClose: () -> Void

    @State private var setup = FirmwareSetup()
    @State private var westProposal = ConfigEditProposal.notNeeded
    @State private var buildProposal = ConfigEditProposal.notNeeded
    /// The include entry the user picked as the central half
    @State private var centralChoice: Int?
    /// Steps the user wants to do by hand, by file
    @State private var doingByHand: Set<String> = []
    @State private var notice: (text: String, isError: Bool)?
    @State private var copiedCode: String?

    private let recheck = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private var configFolder: URL? {
        appState.zmkConfigPath.isEmpty ? nil : URL(fileURLWithPath: appState.zmkConfigPath)
    }

    private var isGitRepository: Bool {
        guard let folder = configFolder else { return false }
        return FileManager.default.fileExists(atPath: folder.appendingPathComponent(".git").path)
    }

    /// The keyboard answers over ZMK Studio, so the new firmware is on it
    private var keyboardAnswers: Bool {
        appState.liveDeviceName != nil
            && [.loaded, .saved, .locked].contains(appState.keyboardKeymapStatus)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Set up your firmware")
                            .font(.title2.bold())
                        Text("For the live layer and reading the keymap, your zmk-config needs two modules and ZMK Studio. The app checks your files, shows each change before it makes it, and leaves building and flashing to you.")
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    folderRow

                    if let notice = notice {
                        Label(notice.text, systemImage: notice.isError ? "exclamationmark.triangle" : "checkmark.circle")
                            .foregroundColor(notice.isError ? .orange : .green)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    step(1, done: configFolder != nil && setup.hasModules, title: "Add the modules", file: FirmwareEdits.westFile) {
                        proposalContent(westProposal, file: FirmwareEdits.westFile, what: "the two modules") {
                            Text("Add these under remotes:")
                            codeBlock("""
                                - name: zzeneg
                                  url-base: https://github.com/zzeneg
                                - name: srwi
                                  url-base: https://github.com/srwi
                            """)
                            Text("and these under projects:")
                            codeBlock("""
                                - name: zmk-raw-hid
                                  remote: zzeneg
                                  revision: main
                                - name: zmk-keypeek-layer-notifier
                                  remote: srwi
                                  revision: master
                            """)
                        }
                    }

                    step(2, done: configFolder != nil && setup.hasRawHID && setup.hasStudio, title: "Turn on Raw HID and ZMK Studio", file: FirmwareEdits.buildFile) {
                        proposalContent(buildProposal, file: FirmwareEdits.buildFile, what: "Raw HID and ZMK Studio for the central half") {
                            Text("In the entry of the central half, add raw_hid_adapter to its shields and turn on ZMK Studio. Only the central half needs it:")
                            codeBlock("""
                              - board: \(setup.board)
                                shield: \(setup.centralShield) raw_hid_adapter
                                snippet: studio-rpc-usb-uart
                                cmake-args: -DCONFIG_ZMK_STUDIO=y
                            """)
                        }
                    }

                    step(3, done: configFolder != nil && setup.hasUnlockKey, title: "Put the unlock key on your keymap", file: setup.keymapFile) {
                        Text("ZMK Studio stays locked until you press this key. Only you know where it fits: a key you rarely use, like next to your Bluetooth or reset keys.")
                        codeBlock("&studio_unlock")
                    }

                    step(4, done: keyboardAnswers, title: "Build, flash and pair again", file: nil) {
                        Text("Commit and push your zmk-config: GitHub Actions builds the firmware. Flash the central half with it, then remove the keyboard in System Settings → Bluetooth and pair it again. macOS only sees the new connection after that.")
                        if appState.liveDeviceName != nil, appState.keyboardKeymapStatus == .failed {
                            Label("\(appState.liveDeviceName ?? "The keyboard") is connected but ZMK Studio doesn't answer. Check step 2.", systemImage: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                        } else {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Waiting for the keyboard…")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding(24)
            }

            Divider()

            HStack {
                Spacer()
                Button("Back", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(minWidth: 560, minHeight: 520)
        .onAppear {
            suggestFolder()
            recheckFiles()
        }
        .onReceive(recheck) { _ in recheckFiles() }
        .onChange(of: appState.zmkConfigPath) { _ in
            centralChoice = nil
            notice = nil
            recheckFiles()
        }
        .onChange(of: centralChoice) { _ in recheckFiles() }
    }

    // MARK: - Folder

    private var folderRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .foregroundColor(.secondary)
            if let folder = configFolder {
                Text((folder.path as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("Choose your zmk-config, the folder with build.yaml")
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(configFolder == nil ? "Choose…" : "Change…") { chooseFolder() }
                .controlSize(.small)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
    }

    /// A loaded keymap file usually sits in the zmk-config's config folder
    private func suggestFolder() {
        guard appState.zmkConfigPath.isEmpty, let keymapPath = viewModel.currentFilePath else { return }
        let folder = URL(fileURLWithPath: keymapPath).deletingLastPathComponent()
        appState.zmkConfigPath = FirmwareSetup.configRoot(for: folder).path
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose your zmk-config"
        panel.message = "The folder with build.yaml and the config folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = configFolder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        appState.zmkConfigPath = FirmwareSetup.configRoot(for: url).path
    }

    private func recheckFiles() {
        guard let folder = configFolder else {
            setup = FirmwareSetup()
            westProposal = .notNeeded
            buildProposal = .notNeeded
            return
        }
        setup = FirmwareSetup.check(folder)
        westProposal = FirmwareEdits.addModules(toWest: read(FirmwareEdits.westFile, in: folder))
        buildProposal = FirmwareEdits.enableRawHIDAndStudio(inBuild: read(FirmwareEdits.buildFile, in: folder), central: centralChoice)
    }

    private func read(_ file: String, in folder: URL) -> String {
        (try? String(contentsOf: folder.appendingPathComponent(file), encoding: .utf8)) ?? ""
    }

    // MARK: - Changes

    /// The proposed change with now and after, or the manual way when the
    /// app can't change the file safely or the user prefers it
    @ViewBuilder
    private func proposalContent<Manual: View>(
        _ proposal: ConfigEditProposal, file: String, what: String,
        @ViewBuilder manual: () -> Manual
    ) -> some View {
        switch proposal {
        case let .edit(edit) where configFolder != nil && !doingByHand.contains(file):
            Text("The app can add \(what) to \(file) for you:")
            ForEach(Array(EditExcerpt.excerpts(of: edit).enumerated()), id: \.offset) { _, excerpt in
                excerptView(excerpt)
            }
            HStack {
                Button("Make This Change") { apply(edit) }
                    .buttonStyle(.borderedProminent)
                Button("I'll Do It Myself") { doingByHand.insert(file) }
                Spacer()
            }
        case let .chooseCentral(entries) where configFolder != nil && !doingByHand.contains(file):
            Text("Which entry builds your central half? It's the half that connects to the computer; with a dongle, it's the dongle.")
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                    Button {
                        centralChoice = index
                    } label: {
                        Label(entry, systemImage: centralChoice == index ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 12, design: .monospaced))
                    }
                    .buttonStyle(.plain)
                }
            }
            Button("I'll Do It Myself") { doingByHand.insert(file) }
        case let .manual(reason) where configFolder != nil:
            Label(reason, systemImage: "hand.raised")
                .foregroundColor(.secondary)
            manual()
        default:
            manual()
        }
    }

    private func apply(_ edit: ConfigEdit) {
        guard let folder = configFolder else { return }
        do {
            try FirmwareEdits.apply(edit, in: folder)
            let undo = isGitRepository ? " To undo it: git checkout -- \(edit.file)" : ""
            notice = ("Changed \(edit.file).\(undo)", false)
        } catch FirmwareEdits.ApplyError.fileChanged {
            notice = ("\(edit.file) changed meanwhile, so nothing was written. Check the change again.", true)
        } catch {
            notice = ("Couldn't write \(edit.file): \(error.localizedDescription)", true)
        }
        recheckFiles()
    }

    private func excerptView(_ excerpt: EditExcerpt) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            excerptLines("Now", excerpt.before, highlight: Color.red)
            excerptLines("After the change", excerpt.after, highlight: Color.green)
        }
    }

    private func excerptLines(_ title: String, _ lines: [EditExcerpt.Line], highlight: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.bold())
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    HStack(spacing: 8) {
                        Text("\(line.number)")
                            .foregroundColor(.secondary)
                            .frame(width: 28, alignment: .trailing)
                        Text(line.text.isEmpty ? " " : line.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.system(size: 11.5, design: .monospaced))
                    .padding(.vertical, 1)
                    .background(line.changed ? highlight.opacity(0.18) : Color.clear)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .textSelection(.enabled)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
        }
    }

    // MARK: - Steps

    /// A done step shrinks to its title, so the open ones stand out
    private func step<Content: View>(
        _ number: Int, done: Bool, title: String, file: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(done ? Color.green : Color.accentColor.opacity(0.15))
                    .frame(width: 24, height: 24)
                if done {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                } else {
                    Text("\(number)")
                        .font(.caption.bold())
                        .foregroundColor(.accentColor)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .bold()
                        .foregroundColor(done ? .secondary : .primary)
                    if let file = file {
                        fileLabel(file)
                    }
                }
                if !done {
                    content()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// The step's file; opens in the editor once the zmk-config is known
    @ViewBuilder
    private func fileLabel(_ file: String) -> some View {
        let label = Text(file).font(.system(size: 11, design: .monospaced))
        if let url = configFolder?.appendingPathComponent(file),
           FileManager.default.fileExists(atPath: url.path) {
            Button {
                appState.openInEditor(url)
            } label: {
                HStack(spacing: 3) {
                    label
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 10))
                }
            }
            .buttonStyle(.link)
            .help("Open \(file) in your editor")
        } else {
            label.foregroundColor(.secondary)
        }
    }

    private func codeBlock(_ code: String) -> some View {
        HStack(alignment: .top) {
            Text(code)
                .font(.system(size: 11.5, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code, forType: .string)
                copiedCode = code
            } label: {
                Label(copiedCode == code ? "Copied" : "Copy", systemImage: copiedCode == code ? "checkmark" : "doc.on.doc")
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
    }
}
