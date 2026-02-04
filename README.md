# ZMK Keymap Viewer

A lightweight macOS menu bar app that displays your ZMK keymap bindings in a visual 2D grid. Perfect for when you're learning a new layer or can't remember where you put that special key.

<img width="751" alt="ZMK Keymap Viewer" src="assets/keymap_screenshot.png" />

## Disclaimer: This app is completely based on AI-output.

![macOS](https://img.shields.io/badge/macOS-13.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9+-orange)
![License](https://img.shields.io/badge/license-MIT-green)

<!-- 
## Screenshot
![ZMK Keymap Viewer Screenshot](screenshot.png)
-->

---

## ✨ Features

| Feature | Description |
|---------|-------------|
| 🎹 **Menu bar app** | Always one click away - lives in your menu bar |
| 📂 **Paste any path** | Simply paste the path to your ZMK keymap file |
| 🔄 **Layer switching** | Instantly switch between all your layers |
| ⌨️ **Dynamic layouts** | Auto-detects keyboard size (Sweep, Corne, Sofle, Lily58, etc.) |
| 👁️ **HUD Mode** | Transparent, floating window overlay for reference while working |
| ⚡ **Global Shortcut** | Toggle visibility instantly (Default: `Cmd+Shift+K`) |
| 💬 **Tooltips** | Hover over keys to see raw binding code |
| 📝 **Open in editor** | Jump straight to editing your keymap |
| 🕐 **Recent keymaps** | Quick access to previously loaded files |
| 🚀 **Auto-load** | Remembers and loads your last keymap on launch |

---

## 📥 Installation

### Option 1: Download (Recommended)

1. Go to [**Releases**](../../releases/latest)
2. Download `ZMK-Keymap-Viewer.dmg`
3. Open the DMG and drag **ZMK Keymap Viewer** to your Applications folder
4. **First launch:** Right-click the app → **Open** → click **Open** in the dialog
5. After that, launch normally from Applications or Spotlight

> **Why right-click?** The app isn't notarized with Apple, so macOS shows a warning. Right-click → Open bypasses this for apps you trust.

### Option 2: Build from Source

Requires Xcode Command Line Tools and Swift 5.9+.

```bash
# Clone the repo
git clone https://github.com/sebietter/ZMK-keymap-viewer.git
cd ZMK-keymap-viewer

# Build release binary
swift build -c release

# Run directly
.build/release/ZMKKeymapViewer

# Or create an app bundle
mkdir -p "ZMK Keymap Viewer.app/Contents/MacOS"
cp .build/release/ZMKKeymapViewer "ZMK Keymap Viewer.app/Contents/MacOS/"
```

---

## 🚀 Quick Start

1. **Click the ⌨️ icon** in your menu bar
2. **Paste the full path** to your `.keymap` file and click **Load**  
   (e.g., `/Users/you/zmk-config/config/cradio.keymap`)
3. **Click a layer tab** to view that layer's bindings
4. **Hover over keys** to see the raw ZMK binding code
5. **Press `Cmd+Shift+K`** to toggle the HUD overlay
6. **Done!** Your keymap is now always one click away

### Tips

- Use **Recent** dropdown to quickly switch between keymaps
- Click **Open in Editor** to jump to your keymap file
- Press **Enter** after pasting a path to load immediately
- The app **auto-loads** your last keymap when you reopen it

---

## ⌨️ Supported Keyboards

Auto-detects layout based on key count:

| Keys | Layout |
|------|--------|
| 34 | Sweep, Cradio, Ferris |
| 42 | Corne, Crkbd |
| 58 | Sofle, Lily58 Pro |
| Other | Generic split layout |

> insert your keymap and tell me how it went :)

---

## 👁️ HUD Mode

The HUD is an always-on-top overlay that floats above your other windows — perfect for quick reference while learning a new layout.

<img width="700" alt="HUD Mode" src="assets/hud_screenshot.png" />

Customize the HUD's opacity and auto-hide timer in Settings:

<img width="500" alt="Settings" src="assets/settings_screenshot.png" />

**Features:**
- **Toggle with `Cmd+Shift+K`** (customizable in settings)
- **Auto-fades** after a few seconds of inactivity
- **Wakes up** when you hover over it or press any key
- **Resizable & draggable** — position it anywhere on screen
- **Remembers position** between launches

> **Want better support for your keyboard?** Open an issue with your layout details!

---

## 🛠️ How It Works

The app parses your `.keymap` file and extracts:
- All layers defined in the `keymap {}` block
- Bindings like `&kp`, `&lt`, `&mt`, `&trans`, `&bt`, and custom behaviors
- Layer names from comments (e.g., `// Base` or `/* Num */`)

It then displays them in a visual grid matching your keyboard's physical layout.

---

## 🤝 Contributing

Contributions welcome! Some ideas:

- [ ] Improve visualization for Combos / Shortcuts
- [ ] Parse combos and macros
- [ ] Export layout as image
- [ ] Live file watching for auto-reload
- [ ] Support for Windows and Linux
- [ ] Support for QMK on top of ZMK
- [ ] File picker for keymap insertion (could not get this to run, hence the file path solution)
- [ ] Alias to show what shortcuts acutally do --> e.g. &kp LS(LA(2)) //€
---

## 🙋 Looking for Collaborators!

I can only do as much coding as I have AI credits in the bank, lol. If you're interested in contributing, improving, or maintaining this project, **please reach out!** Open an issue, submit a PR, or just fork it and make it better.

---

## 📦 Built With

- **SwiftUI + AppKit** - Native macOS experience
- **Swift Package Manager** - Simple build system
- **100% vibe coded with GitHub Copilot** ✨
- Love and dedication for the community

---

## ⚠️ Disclaimer

**This tool was generated almost entirely by AI** (GitHub Copilot / Claude). While it works for me, you should treat it with the appropriate level of suspicion you'd give any AI-generated code. Use at your own risk, review the code if you're paranoid (you should be), and don't blame the robots when things go sideways.

---
## 📄 License

MIT © Intersebbtor
