// Draws the app icon and writes assets/AppIcon.icns.
// Same schematic Sweep as the menu bar icon (SplitKeyboardIcon): per half a
// 3×3 key grid and a wide thumb key under the inner columns. One thumb key
// lights up like a held key in the HUD.
//
// Usage: swift scripts/make-app-icon.swift [output.icns]

import AppKit

let canvas: CGFloat = 1024

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func fillKey(_ rect: NSRect, _ fill: NSColor) {
    fill.setFill()
    NSBezierPath(roundedRect: rect, xRadius: 16, yRadius: 16).fill()
}

func drawIcon() {
    // Body on the macOS icon grid: 824×824, centered, with a soft drop shadow
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.shadowBlurRadius = 24
    shadow.set()
    color(0x1B1D22).setFill()
    bodyPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(starting: color(0x30333A), ending: color(0x16181C))!.draw(in: bodyPath, angle: -90)
    color(0xFFFFFF, alpha: 0.08).setStroke()
    let rim = NSBezierPath(roundedRect: body.insetBy(dx: 1.5, dy: 1.5), xRadius: 184, yRadius: 184)
    rim.lineWidth = 3
    rim.stroke()

    // Keyboard halves
    let key: CGFloat = 72
    let gap: CGFloat = 22
    let thumbGap: CGFloat = 36
    let thumbWidth: CGFloat = 150
    let halfWidth = 3 * key + 2 * gap
    let middleGap: CGFloat = 124
    let height = 4 * key + 2 * gap + thumbGap
    let left = (canvas - 2 * halfWidth - middleGap) / 2
    let bottom = (canvas - height) / 2

    let keyColor = color(0xD9DCE1)
    let heldColor = color(0x3B82F6)

    for (index, originX) in [left, left + halfWidth + middleGap].enumerated() {
        let isLeft = index == 0
        let gridY = bottom + key + thumbGap
        for row in 0..<3 {
            for column in 0..<3 {
                fillKey(NSRect(
                    x: originX + CGFloat(column) * (key + gap),
                    y: gridY + CGFloat(row) * (key + gap),
                    width: key,
                    height: key
                ), keyColor)
            }
        }
        // The thumb key sits under the inner columns, toward the middle
        let thumbX = isLeft ? originX + halfWidth - thumbWidth : originX
        fillKey(NSRect(x: thumbX, y: bottom, width: thumbWidth, height: key), isLeft ? keyColor : heldColor)
    }
}

func pngData(size: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: canvas, height: canvas)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "assets/AppIcon.icns"
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for points in [16, 32, 128, 256, 512] {
    try pngData(size: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try pngData(size: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Wrote \(output)")
