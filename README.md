# ZMK Keymap Viewer

> **Quickly view your ZMK keyboard layers without leaving your workflow.**

A lightweight macOS menu bar app that displays your ZMK keymap bindings in a visual 2D grid. Perfect for when you're learning a new layer or can't remember where you put that special key.

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
| 📂 **Load any .keymap** | Point to your local ZMK keymap file |
| 🔄 **Layer switching** | Instantly switch between all your layers |
| ⌨️ **2D keyboard grid** | See your bindings in a visual keyboard layout |
| 📝 **Open in editor** | Jump straight to editing your keymap |
| 🕐 **Recent keymaps** | Quick access to previously loaded files |
| 🚀 **Auto-load** | Remembers and loads your last keymap on launch |

---

## 📥 Installation

### Option 1: Download (Recommended)

1. Go to [**Releases**](../../releases/latest)
2. Download `ZMK-Keymap-Viewer.dmg`
3. Open the DMG and drag **ZMK Keymap Viewer** to your Applications folder
4. Launch from Applications or Spotlight (search "ZMK")

> **Note:** On first launch, macOS may ask you to allow the app. Go to **System Settings → Privacy & Security** and click "Open Anyway".

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
2. **Click "Select File..."** and paste the full path to your `.keymap` file  
   (e.g., `~/zmk-config/config/cradio.keymap`)
3. **Click a layer button** to view that layer's bindings
4. **Done!** Your keymap is now always one click away

### Tips

- Use **Recent** dropdown to quickly switch between keymaps
- Click **Open in Editor** to jump to your keymap file
- The app **auto-loads** your last keymap when you reopen it

---

## ⌨️ Supported Keyboards

Currently optimized for **split 34-key layouts**:

- ✅ **Cradio / Sweep**
- ✅ **Ferris**
- ✅ Any 34-key ZMK board

> **Want support for your keyboard?** Open an issue with your layout and I'll add it!

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

- [ ] Add more keyboard layouts (Corne, Lily58, etc.)
- [ ] Parse combos and macros
- [ ] Dark/light theme toggle
- [ ] Export layout as image

---

## 📦 Built With

- **SwiftUI + AppKit** - Native macOS experience
- **Swift Package Manager** - Simple build system
- **100% vibe coded with GitHub Copilot** ✨

---

## 📄 License

MIT © Sebastian Stierstorfer
