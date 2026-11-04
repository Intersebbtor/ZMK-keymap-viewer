import SwiftUI
import UniformTypeIdentifiers

/// Pages of the setup window
enum SetupPage {
    /// Two ways to a keymap: from the keyboard or from a file
    case start
    /// The zmk-config changes for the live layer and ZMK Studio
    case firmware
    /// The keymap is there: what the labels show, how to name keys
    case done
}

/// The setup in a window of its own: the first start, and setting up
/// another keyboard from the settings. Everyday use stays in the menu bar.
struct SetupView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var viewModel: KeymapViewModel
    @State private var isDropTargeted = false

    var body: some View {
        Group {
            switch appState.setupPage {
            case .start:
                startPage
            case .firmware:
                FirmwareSetupView(onClose: { appState.setupPage = .start })
            case .done:
                donePage
            }
        }
        .frame(minWidth: 640, minHeight: 520)
        // The setup moves on by itself once a keymap arrives
        .onChange(of: appState.keyboardKeymapStatus) { status in
            if status == .loaded, appState.setupPage == .start {
                appState.setupPage = .done
            }
        }
        .onChange(of: viewModel.currentFilePath) { path in
            if path != nil, appState.setupPage == .start {
                appState.setupPage = .done
            }
        }
    }

    // MARK: - Start

    private var startPage: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(nsImage: SplitKeyboardIcon.image(layer: nil))
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96)
                    .foregroundColor(.accentColor)
                Text("Show your keymap")
                    .font(.title.bold())
                Text("Read it straight from your keyboard, or load your .keymap file.")
                    .foregroundColor(.secondary)
            }

            HStack(alignment: .top, spacing: 16) {
                card(title: "From your keyboard", systemImage: "dot.radiowaves.left.and.right") {
                    keyboardContent
                }
                card(title: "From a file", systemImage: "doc.text") {
                    Text("Can't or don't want to unlock ZMK Studio? Load the .keymap file from your zmk-config instead. The app follows your edits.")
                    Button {
                        appState.chooseKeymapFile()
                    } label: {
                        Label("Choose File…", systemImage: "folder")
                    }
                    .buttonStyle(.borderedProminent)
                    Text("or drop it on this window")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            // Both cards as tall as the taller one's content
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: appState.loadDroppedKeymap)
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor, lineWidth: 3)
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
    }

    private func card<Content: View>(title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content()
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 200, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2)))
    }

    /// Walks through connecting and unlocking; it moves on by itself
    @ViewBuilder
    private var keyboardContent: some View {
        let device = appState.liveDeviceName ?? "Your keyboard"
        let firmwareLink = Button("Set up my firmware…") { appState.setupPage = .firmware }
            .buttonStyle(.link)
            .font(.caption)
        if !appState.readKeymapFromKeyboard {
            Text("Reading the keymap from the keyboard is turned off.")
            Button("Turn On") { appState.readKeymapFromKeyboard = true }
        } else if appState.liveDeviceName == nil {
            Text("Connect your ZMK keyboard over USB or Bluetooth. Its firmware needs ZMK Studio and the layer notifier module.")
            waitingRow("Waiting for a keyboard…")
            firmwareLink
        } else {
            switch appState.keyboardKeymapStatus {
            case .locked:
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lock.fill")
                        .font(.title2)
                        .foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(device) is locked")
                            .bold()
                        Text("Press **&studio_unlock** on your keyboard. ZMK Studio keeps the keymap locked until then.")
                    }
                }
                waitingRow("Listening for the unlock…")
                Button("No unlock key yet? Set up my firmware…") { appState.setupPage = .firmware }
                    .buttonStyle(.link)
                    .font(.caption)
            case .failed:
                Text("\(device) didn't send its keymap. Its firmware might not have ZMK Studio.")
                Button("Try Again") { appState.refreshKeyboardKeymap() }
                firmwareLink
            case .loaded, .saved:
                Label("\(device)'s keymap is loaded.", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Button("Continue") { appState.setupPage = .done }
                    .buttonStyle(.borderedProminent)
            case .idle, .loading:
                Text("Connected to \(device).")
                waitingRow("Reading the keymap…")
            }
        }
    }

    private func waitingRow(_ text: String) -> some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Done

    /// What the labels show, how to name shortcuts and macros, and where the
    /// keymap lives from now on
    private var donePage: some View {
        VStack(spacing: 22) {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.green)
                Text("Your keymap is ready")
                    .font(.title.bold())
                HStack(spacing: 6) {
                    Text("It lives in the menu bar: click")
                    Image(nsImage: SplitKeyboardIcon.image(layer: nil))
                        .renderingMode(.template)
                    Text("to see it. The HUD shortcut shows it over any window.")
                }
                .foregroundColor(.secondary)
            }

            Divider()
                .frame(maxWidth: 480)

            VStack(spacing: 10) {
                Text("Name your keys")
                    .font(.headline)
                Text("Keys that type a character show it, like € or ß. Shortcuts and macros show their keys, so give them a name you recognize:")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 480)
                HStack(spacing: 12) {
                    guideKey("⇧+⌘+4")
                    Image(systemName: "arrow.right")
                        .foregroundColor(.secondary)
                    guideKey("Screenshot", highlighted: true)
                }
                Label("Right-click a key and choose Name This Key…", systemImage: "cursorarrow.click.2")
                    .font(.callout)
            }

            Button("Done") { appState.closeSetup() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func guideKey(_ label: String, highlighted: Bool = false) -> some View {
        Text(label)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .frame(minWidth: 54, minHeight: 44)
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor)))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(highlighted ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: highlighted ? 2 : 1)
            )
    }
}
