# Release v1.6.0

## Highlights
- **Keymap Straight from the Keyboard**: With ZMK Studio in the firmware, the app reads layers, bindings and the physical layout from the keyboard itself, over the same Raw HID connection as the live layer. No file needed, and it always shows what is really on the board. The app only reads; it never changes the keymap.
- **Setup Window**: The first start opens a setup window: connect the keyboard and press `&studio_unlock` (the app listens and loads the keymap by itself), or choose a `.keymap` file for keyboards without Studio. Everyday use stays in the menu bar; Settings → Set Up a Keyboard… opens the setup again. Choose File… and drag and drop replace the path field.
- **Firmware Setup**: Set up my firmware… checks your zmk-config and ticks off what's done. It shows the changes to `west.yml` and `build.yaml` as now and after and makes them on a click, keeping your comments and other shields; files it doesn't fully understand get examples to copy instead. It walks you through placing `&studio_unlock`, building, flashing and pairing again, and ticks the last step off once the keyboard answers.
- **Remembered Keymap**: The keymap read last shows right away at launch and after the keyboard restarts locked, so you unlock once, not after every restart.
- **Typed Characters on the Keys**: Keys show what they type in your macOS keyboard layout: `⌥⇧2` shows €, `⌥S` shows ß, and with the German layout the SEMI key shows Ö. Labels follow input source changes.
- **Name Keys with a Right-Click**: Give shortcuts and macros a name (`⇧⌘4` → Screenshot). A name applies wherever the same binding sits, for keymaps from the keyboard and from a file.
- **New Icons**: The menu bar shows a schematic split keyboard with the active layer number between the halves, and the app has a matching icon.

## Changes
- `/* =name */` comments in the keymap file no longer name keys; use a right-click instead. Editors like the ZMK keymap editor drop these comments anyway, and they never reach the keyboard.
- File paths show the home folder as `~`.
- Modifier labels follow the macOS order ⌃⌥⇧⌘.
- Settings → Editor opens keymap and config files with a command like `code`.

## Commits Since v1.5.0
- feat: walk through the unlock key and flashing step by step
- feat: setup window that makes the zmk-config changes after a preview
- feat: open files with an editor command from the settings
- feat: firmware setup guide that checks the zmk-config
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
