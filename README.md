# ZMK Keymap Viewer

A lightweight macOS menu bar app that displays your ZMK keymap bindings in a visual 2D grid. Perfect for when you're learning a new layer or can't remember where you put that special key.

With two small firmware modules it follows your keyboard live: it shows the layer you are on and lights up the keys you press, in a floating HUD that stays out of your way.

<img width="751" alt="ZMK Keymap Viewer" src="assets/keymap_screenshot.png" />

![macOS](https://img.shields.io/badge/macOS-13.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9+-orange)
![License](https://img.shields.io/badge/license-MIT-green)

---

## ✨ Features

- 🎹 **Menu bar app** — Always one click away
- 🔄 **Layer switching** — Instantly switch between all your layers
- ⌨️ **Auto-detect layout** — Sweep, Corne, Sofle, Lily58, and more
- 👁️ [**HUD Mode**](#️-hud-mode) — Transparent floating overlay (toggle with `Cmd+Shift+K`)
- 📡 [**Live layer**](#-live-layer) — Follows the layer you're on, over USB or Bluetooth
- ✨ [**Key highlighting**](#-live-layer) — Keys light up in the HUD while you hold them
- 🔢 **Layer in the menu bar** — The menu bar icon shows the active layer number
- 📝 [**Alias support**](#-alias-comments) — Add `/* =€ */` comments to show custom labels
- 🔴 **Live reload** — Watches your keymap file for changes
- 📄 **PDF Export** — Export your layout to PDF
- 🔄 **Auto-update** — Checks for updates and downloads them in-app

---

## 📥 Installation

1. Go to [**Releases**](../../releases/latest)
2. Download `ZMK-Keymap-Viewer-vX.X.X.dmg`
3. Open the DMG and drag **ZMK Keymap Viewer** to Applications
4. **First launch:** The app is not notarized. If macOS refuses to open it or says it is damaged, open **System Settings → Privacy & Security** and click **Open Anyway**, or run:

   ```bash
   xattr -dr com.apple.quarantine "/Applications/ZMK Keymap Viewer.app"
   ```

> **Build from source:** `./scripts/build-release.sh` builds the app bundle and the DMG (the version comes from `appVersion` in `ZMKKeymapViewer.swift`).

---

## 🚀 Quick Start

1. Click the ⌨️ icon in your menu bar
2. Paste the path to your `.keymap` file and click **Load**
3. Click layer tabs to switch views (or let the [live layer](#-live-layer) do it)
4. Press `Cmd+Shift+K` to toggle HUD mode

---

## 👁️ HUD Mode

<img width="700" alt="HUD Mode" src="assets/hud_screenshot.png" />

- **Always-on-top** floating overlay
- **Auto-fades** after inactivity, wakes on hover, on key presses and on layer changes
- **Stays visible while you hold a key**, so a held layer (`&mo`, `&lt`, `&mt`) stays on screen while you look for a key
- **Draggable** by the handle bar at the top, **resizable** from any edge or corner
- Customize opacity, blur and timeout in Settings

---

## 📡 Live Layer

With two small firmware modules, the app knows what happens on your keyboard:

- **Active layer:** The menu and the HUD switch to the layer you are on, and the menu bar icon shows its number (a plain keyboard on the base layer).
- **Held keys:** Keys light up in the HUD while you hold them, so you see at a glance which key you hit.
- **No flicker:** The HUD wakes on every key press, not only on layer changes, and doesn't fade while a key is held.

Works over USB and Bluetooth, no extra macOS permission needed. Settings → Live Layer shows whether the keyboard is connected and which layer it is on.

Clicking a layer tab still works; it holds until your next layer change on the keyboard. Following the keyboard and the menu bar number can be turned off in Settings → Live Layer.

**Firmware setup** (in your `zmk-config`, uses the same modules as [KeyPeek](https://github.com/srwi/keypeek)):

1. Add the modules to `config/west.yml`:

   ```yaml
   manifest:
     remotes:
       - name: zzeneg
         url-base: https://github.com/zzeneg
       - name: srwi
         url-base: https://github.com/srwi
     projects:
       - name: zmk-raw-hid
         remote: zzeneg
         revision: main
       - name: zmk-keypeek-layer-notifier
         remote: srwi
         revision: master
   ```

2. Add the `raw_hid_adapter` shield and ZMK Studio to the central half in `build.yaml` (for splits only the central half needs it):

   ```yaml
   include:
     - board: nice_nano_v2
       shield: cradio_left raw_hid_adapter
       snippet: studio-rpc-usb-uart
       cmake-args: -DCONFIG_ZMK_STUDIO=y
   ```

3. Flash the central half, then **remove the keyboard in System Settings → Bluetooth and pair it again**. macOS caches the keyboard's services and only sees the new Raw HID interface after re-pairing.

> The live layer is the layer *number*. The names come from your `.keymap` file, so keep the file in sync if you reorder or add layers with ZMK Studio.

---

## 📝 Alias Comments

Add custom labels to your bindings using comments:

```c
&kp LS(LA(N2)) /* =€ */     // Shows "€" instead of the binding
&kp LC(C) /* =Copy */          // Shows "Copy"
```

---

## 🛠️ How It Works

The app parses your `.keymap` file and extracts:
- All layers defined in the `keymap {}` block
- Bindings like `&kp`, `&lt`, `&mt`, `&trans`, `&bt`, and custom behaviors
- Layer names from comments

For the live layer it listens for the Raw HID reports of [zmk-keypeek-layer-notifier](https://github.com/srwi/zmk-keypeek-layer-notifier) (usage page `0xFF60`): a layer mask on every layer change and a key position on every press and release. The key position is the binding's index in the keymap, so highlighting needs no extra layout config.

---

## 🤝 Contributing

Ideas and PRs welcome! Some things on the radar:

- [ ] Windows/Linux support
- [ ] QMK support

---

## 📄 License

MIT © Intersebbtor

---

*Built with SwiftUI + AppKit, 100% vibe coded with GitHub Copilot. From the community, for the community.* ✨
