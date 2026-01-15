# ZMK Keymap Viewer

A lightweight macOS menu bar app for visualizing your ZMK keyboard keymaps.

![macOS](https://img.shields.io/badge/macOS-13.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9+-orange)

## Features

- 🎹 **Menu bar app** - Always accessible from your menu bar
- 📂 **Load any .keymap file** - Just paste the path to your keymap
- 🔄 **Layer switching** - View all your keymap layers
- ⌨️ **2D keyboard grid** - Visual layout for Cradio/Sweep (34 keys)
- 📝 **Open in editor** - Quick access to edit your keymap
- 🕐 **Recent keymaps** - Remembers your last used keymaps
- 🚀 **Auto-load** - Automatically loads your most recent keymap on launch

## Installation

### Download (Recommended)

1. Go to [**Releases**](../../releases)
2. Download the latest `ZMK-Keymap-Viewer.dmg`
3. Open the DMG and drag the app to your Applications folder
4. Launch from Applications or Spotlight

### Build from Source

```bash
git clone https://github.com/yourusername/ZMK-keymap-viewer.git
cd ZMK-keymap-viewer
swift build -c release
```

The binary will be at `.build/release/ZMKKeymapViewer`

## Usage

1. Click the ⌨️ keyboard icon in your menu bar
2. Click "Select File..." and paste the path to your `.keymap` file
3. Select a layer to view its bindings
4. Use "Open in Editor" to edit your keymap

## Supported Keyboards

Currently optimized for:
- **Cradio/Sweep** (34 keys)

More layouts coming soon!

## Built With

- SwiftUI + AppKit
- Swift Package Manager
- 100% vibe coded with GitHub Copilot ✨

## License

MIT
