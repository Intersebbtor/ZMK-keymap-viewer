import AppKit

/// Menu bar icon of a split keyboard with the layer number between the halves.
/// Each half is a schematic Sweep half: a key grid and a wide thumb key under
/// the inner columns. Drawn in code as a template image, so it follows the
/// menu bar's appearance, and cached per layer.
enum SplitKeyboardIcon {
    /// Size with a single digit; every further digit widens the icon
    static let size = NSSize(width: 35, height: 16)
    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .bold)

    private static var cache: [Int: NSImage] = [:]

    static func image(layer: Int) -> NSImage {
        if let cached = cache[layer] {
            return cached
        }
        let text = "\(layer)" as NSString
        let digitWidth = ("0" as NSString).size(withAttributes: [.font: font]).width
        let imageSize = NSSize(width: size.width + CGFloat(text.length - 1) * digitWidth, height: size.height)
        let image = NSImage(size: imageSize, flipped: false) { _ in
            draw(text, in: imageSize)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Layer \(layer)"
        cache[layer] = image
        return image
    }

    private static func draw(_ text: NSString, in size: NSSize) {
        NSColor.black.set()
        drawLeftHalf()
        // The right half is the left one mirrored
        NSGraphicsContext.saveGraphicsState()
        let mirror = NSAffineTransform()
        mirror.translateX(by: size.width, yBy: 0)
        mirror.scaleX(by: -1, yBy: 1)
        mirror.concat()
        drawLeftHalf()
        NSGraphicsContext.restoreGraphicsState()

        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let textWidth = text.size(withAttributes: attributes).width
        // Center the digit's cap height, not the line box
        let baseline = (size.height - font.capHeight) / 2
        text.draw(at: NSPoint(x: (size.width - textWidth) / 2, y: baseline + font.descender), withAttributes: attributes)
    }

    /// A 3×3 key grid (standing for the 3×5 matrix) and a wide thumb key
    /// under the inner columns
    private static func drawLeftHalf() {
        let key: CGFloat = 2.5
        let gap: CGFloat = 0.8
        let left: CGFloat = 1.0
        let thumbY: CGFloat = 1.6
        let gridY = thumbY + key + 1.0

        for row in 0..<3 {
            for column in 0..<3 {
                fillKey(NSRect(
                    x: left + CGFloat(column) * (key + gap),
                    y: gridY + CGFloat(row) * (key + gap),
                    width: key,
                    height: key
                ))
            }
        }

        let inner = left + 3 * key + 2 * gap
        let thumbWidth: CGFloat = 5.2
        fillKey(NSRect(x: inner - thumbWidth, y: thumbY, width: thumbWidth, height: key))
    }

    private static func fillKey(_ rect: NSRect) {
        NSBezierPath(roundedRect: rect, xRadius: 0.5, yRadius: 0.5).fill()
    }
}
