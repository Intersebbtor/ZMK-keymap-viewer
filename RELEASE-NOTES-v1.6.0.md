# Release v1.6.0

## Highlights
- **Keymap Straight from the Keyboard**: With ZMK Studio in the firmware, the app reads layers, bindings and the physical layout from the keyboard itself, over the same Raw HID connection as the live layer. No file needed, and it always shows what is really on the board. The app only reads; it never changes the keymap.
- **Setup Guide**: The first start walks you through it: connect the keyboard, press `&studio_unlock` (the app listens and loads the keymap by itself), or choose a `.keymap` file for keyboards without Studio. Choose File… and drag and drop replace the path field.
- **Remembered Keymap**: The keymap read last shows right away at launch and after the keyboard restarts locked, so you unlock once, not after every restart.
- **Typed Characters on the Keys**: Keys show what they type in your macOS keyboard layout: `⌥⇧2` shows €, `⌥S` shows ß, and with the German layout the SEMI key shows Ö. Labels follow input source changes.
- **Name Keys with a Right-Click**: Give shortcuts and macros a name (`⇧⌘4` → Screenshot). A name applies wherever the same binding sits, for keymaps from the keyboard and from a file.
- **New Icons**: The menu bar shows a schematic split keyboard with the active layer number between the halves, and the app has a matching icon.

## Changes
- `/* =name */` comments in the keymap file no longer name keys; use a right-click instead. Editors like the ZMK keymap editor drop these comments anyway, and they never reach the keyboard.
- File paths show the home folder as `~`.
- Modifier labels follow the macOS order ⌃⌥⇧⌘.

## Commits Since v1.5.0
- feat: hide the file controls while the keymap comes from the keyboard
- refactor!: drop name comments in the keymap file
- fix: name keys inside the popover and keep the shown layer
- feat: typed characters on the keys, name keys with a right-click
- feat: keep the keymap read last, split icon while disconnected
- feat: setup guide on first start, file picker, listen for the unlock
- fix: labels and unlock detection checked against a real Sweep
- feat: read the keymap from the keyboard over ZMK Studio
- feat: add an app icon matching the menu bar icon
- docs: refresh screenshots and show the home folder as ~
- feat: draw the menu bar icon as a schematic Sweep for every layer

---

**App and DMG are available in this release.**

Thank you for your feedback and contributions!
