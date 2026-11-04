import SwiftUI

/// Walks through the firmware changes in the user's zmk-config, step by
/// step with examples to copy. Once a folder is chosen, the app checks the
/// files every two seconds and ticks off what's done; it never edits them.
struct FirmwareSetupView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var viewModel: KeymapViewModel
    @State private var setup = FirmwareSetup()
    @State private var copiedCode: String?

    private let recheck = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private var configFolder: URL? {
        appState.zmkConfigPath.isEmpty ? nil : URL(fileURLWithPath: appState.zmkConfigPath)
    }

    /// The keyboard answers over ZMK Studio, so the new firmware is on it
    private var keyboardAnswers: Bool {
        appState.liveDeviceName != nil
            && [.loaded, .saved, .locked].contains(appState.keyboardKeymapStatus)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Set up your firmware")
                    .font(.headline.bold())
                Spacer()
                Button(action: { appState.isFirmwareSetupVisible = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("For the live layer and reading the keymap, your zmk-config needs two modules and ZMK Studio. Choose its folder and the app ticks off what's done.")
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    folderRow

                    step(
                        1, done: configFolder != nil && setup.hasModules,
                        title: "Add the modules", file: "config/west.yml"
                    ) {
                        Text("Add these two lines under remotes:")
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

                    step(
                        2, done: configFolder != nil && setup.hasRawHID && setup.hasStudio,
                        title: "Turn on Raw HID and ZMK Studio", file: "build.yaml"
                    ) {
                        Text("Make the entry of the central half (\(setup.centralShield)) look like this. Only the central half needs it.")
                        codeBlock("""
                          - board: \(setup.board)
                            shield: \(setup.centralShield) raw_hid_adapter
                            snippet: studio-rpc-usb-uart
                            cmake-args: -DCONFIG_ZMK_STUDIO=y
                        """)
                    }

                    step(
                        3, done: configFolder != nil && setup.hasUnlockKey,
                        title: "Add a key to unlock ZMK Studio", file: setup.keymapFile
                    ) {
                        Text("ZMK Studio stays locked until you press this key. Put it on a key you rarely use, like next to your Bluetooth or reset keys:")
                        codeBlock("&studio_unlock")
                    }

                    step(
                        4, done: keyboardAnswers,
                        title: "Build, flash and pair again", file: nil
                    ) {
                        Text("Commit and push: GitHub Actions builds the firmware. Flash the central half, then remove the keyboard in System Settings → Bluetooth and pair it again. macOS only sees the new connection after that.")
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
                .padding()
            }
        }
        .onAppear {
            suggestFolder()
            recheckFiles()
        }
        .onReceive(recheck) { _ in recheckFiles() }
        .onChange(of: appState.zmkConfigPath) { _ in recheckFiles() }
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
                Text("No zmk-config chosen")
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(configFolder == nil ? "Choose zmk-config…" : "Change…") { chooseFolder() }
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
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        appState.zmkConfigPath = FirmwareSetup.configRoot(for: url).path
    }

    private func recheckFiles() {
        guard let folder = configFolder else {
            setup = FirmwareSetup()
            return
        }
        setup = FirmwareSetup.check(folder)
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

    /// The step's file; opens in the default editor once the zmk-config is known
    @ViewBuilder
    private func fileLabel(_ file: String) -> some View {
        let label = Text(file).font(.system(size: 11, design: .monospaced))
        if let url = configFolder?.appendingPathComponent(file),
           FileManager.default.fileExists(atPath: url.path) {
            Button {
                NSWorkspace.shared.open(url)
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
