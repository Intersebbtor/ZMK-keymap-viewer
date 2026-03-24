# Release v1.4.0 (2026-02-06)

## Highlights
- **Layer Tab UI Overhaul**: Layer tabs now wrap to multiple rows, are centered, and scroll vertically with a visually distinct background. The scroll area is taller for better usability with many layers.
- **Generalized Layout Detection**: Improved keymap parser to support both split and non-split keyboards, with more robust detection logic.
- **Parser Improvements**: Simplified alias parsing (only /* =alias */ syntax supported), and streamlined code for maintainability.
- **Documentation Updates**: README streamlined and updated to reflect new features and usage.

## Commits Since v1.3.0
- fix: layer tabs scroll vertically with max height to prevent overflow
- fix: properly wrap layer tabs to multiple rows (max 6 per row)
- fix: wrap and center layer labels for many layers
- feat: generalized layout detection with split/non-split support
- Simplify alias parsing: only support /* =alias */ syntax
- Streamline README with updated features list

---

**App and DMG are available in this release.**

Thank you for your feedback and contributions!
