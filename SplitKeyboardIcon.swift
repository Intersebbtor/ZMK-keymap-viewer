import AppKit

/// Menu bar icon of a split keyboard with the layer number between the halves.
/// Drawn in code as a template image, so it follows the menu bar's appearance,
/// and cached per layer.
enum SplitKeyboardIcon {
    static let size = NSSize(width: 35, height: 16)

    private static var cache: [Int: NSImage] = [:]

    static func image(layer: Int) -> NSImage {
        if let cached = cache[layer] {
            return cached
        }
        let image = NSImage(size: size, flipped: false) { _ in
            draw(layer: layer)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Layer \(layer)"
        cache[layer] = image
        return image
    }

    private static func draw(layer: Int) {
        NSColor.black.set()
        let half = NSSize(width: 11.4, height: 9.4)
        let y = (size.height - half.height) / 2
        drawHalf(in: NSRect(origin: NSPoint(x: 0.6, y: y), size: half))
        drawHalf(in: NSRect(origin: NSPoint(x: size.width - 0.6 - half.width, y: y), size: half))

        let font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .bold)
        let text = "\(layer)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let textWidth = text.size(withAttributes: attributes).width
        // Center the digit's cap height, not the line box
        let baseline = (size.height - font.capHeight) / 2
        text.draw(at: NSPoint(x: (size.width - textWidth) / 2, y: baseline + font.descender), withAttributes: attributes)
    }

    /// Outline of one half with a 4×3 grid of keys
    private static func drawHalf(in rect: NSRect) {
        let outline = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
        outline.lineWidth = 1.2
        outline.stroke()

        let columns = 4, rows = 3
        let key: CGFloat = 1.4
        let gapX = (rect.width - CGFloat(columns) * key) / CGFloat(columns + 1)
        let gapY = (rect.height - CGFloat(rows) * key) / CGFloat(rows + 1)
        for row in 0..<rows {
            for column in 0..<columns {
                let origin = NSPoint(
                    x: rect.minX + gapX + CGFloat(column) * (key + gapX),
                    y: rect.minY + gapY + CGFloat(row) * (key + gapY)
                )
                NSBezierPath(rect: NSRect(origin: origin, size: NSSize(width: key, height: key))).fill()
            }
        }
    }
}
