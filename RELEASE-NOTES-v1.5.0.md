# Release v1.5.0 (2026-11-03)

## Highlights
- **Live Layer**: The viewer follows your keyboard's active layer in the menu, the HUD and the menu bar icon. It reads the layer over Raw HID (USB and Bluetooth) from keyboards running [zmk-raw-hid](https://github.com/zzeneg/zmk-raw-hid) and [zmk-keypeek-layer-notifier](https://github.com/srwi/zmk-keypeek-layer-notifier). No Input Monitoring permission needed. See the README for the firmware setup.
- **Held Key Highlighting**: Keys light up in the HUD while you hold them. The HUD doesn't fade while a key is held, so a held layer stays visible while you look for a key.
- **Movable, Resizable HUD**: Drag the HUD by its handle bar and resize it from any edge or corner.
- **Layer Number in the Menu Bar**: Optionally shows the active layer as a fixed-width numbered symbol.

## Fixes
- The menu bar popover stays clickable from launch.
- Settings scroll instead of overflowing the popover, and reopening the popover starts on the keymap again.
- The build script takes the version from the app and names the DMG the way the in-app updater expects.

## Commits Since v1.4.0
- feat: highlight held keys and make the HUD movable and resizable
- fix: create AppState lazily so the menu stays clickable
- fix: show the live layer as a fixed-width menu bar symbol
- docs: describe live layer and its firmware setup
- feat: follow the keyboard's live layer in menu, HUD and menu bar
- feat: decode live layer packets from zmk-keypeek-layer-notifier
- test: update stale tests to current layout and alias behavior

---

**App and DMG are available in this release.**

Thank you for your feedback and contributions!
