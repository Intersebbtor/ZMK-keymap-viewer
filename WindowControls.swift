import SwiftUI
import AppKit

// MARK: - Window Drag Area

/// Moves the window when dragged. SwiftUI content swallows the mouse-down
/// that isMovableByWindowBackground relies on, so the drag is started explicitly.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DragView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }
    }
}

// MARK: - Window Resize Edges

/// Which window edges a resize zone moves.
struct ResizeEdges: OptionSet {
    let rawValue: Int

    static let left = ResizeEdges(rawValue: 1 << 0)
    static let right = ResizeEdges(rawValue: 1 << 1)
    static let top = ResizeEdges(rawValue: 1 << 2)
    static let bottom = ResizeEdges(rawValue: 1 << 3)

    /// New window frame after dragging by (dx, dy) in screen coordinates
    /// (y grows upwards). Keeps the opposite edges fixed and respects `minSize`.
    func resize(_ frame: NSRect, dx: CGFloat, dy: CGFloat, minSize: NSSize) -> NSRect {
        var result = frame
        if contains(.right) {
            result.size.width = max(frame.width + dx, minSize.width)
        }
        if contains(.left) {
            result.size.width = max(frame.width - dx, minSize.width)
            result.origin.x = frame.maxX - result.width
        }
        if contains(.top) {
            result.size.height = max(frame.height + dy, minSize.height)
        }
        if contains(.bottom) {
            result.size.height = max(frame.height - dy, minSize.height)
            result.origin.y = frame.maxY - result.height
        }
        return result
    }
}

/// Invisible resize zones along all edges and corners of the window,
/// for windows without the native resize border.
struct WindowResizeEdges: View {
    var edgeThickness: CGFloat = 6
    var cornerSize: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let innerWidth = max(width - 2 * cornerSize, 0)
            let innerHeight = max(height - 2 * cornerSize, 0)

            ZStack {
                // Edges
                zone(.top, width: innerWidth, height: edgeThickness, x: width / 2, y: edgeThickness / 2)
                zone(.bottom, width: innerWidth, height: edgeThickness, x: width / 2, y: height - edgeThickness / 2)
                zone(.left, width: edgeThickness, height: innerHeight, x: edgeThickness / 2, y: height / 2)
                zone(.right, width: edgeThickness, height: innerHeight, x: width - edgeThickness / 2, y: height / 2)
                // Corners
                zone([.top, .left], width: cornerSize, height: cornerSize, x: cornerSize / 2, y: cornerSize / 2)
                zone([.top, .right], width: cornerSize, height: cornerSize, x: width - cornerSize / 2, y: cornerSize / 2)
                zone([.bottom, .left], width: cornerSize, height: cornerSize, x: cornerSize / 2, y: height - cornerSize / 2)
                zone([.bottom, .right], width: cornerSize, height: cornerSize, x: width - cornerSize / 2, y: height - cornerSize / 2)
            }
        }
    }

    private func zone(_ edges: ResizeEdges, width: CGFloat, height: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        ResizeZone(edges: edges)
            .frame(width: width, height: height)
            .position(x: x, y: y)
    }
}

private struct ResizeZone: NSViewRepresentable {
    let edges: ResizeEdges

    func makeNSView(context: Context) -> NSView {
        ResizeView(edges: edges)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ResizeView: NSView {
        let edges: ResizeEdges
        private var startFrame: NSRect = .zero
        private var startMouse: NSPoint = .zero

        init(edges: ResizeEdges) {
            self.edges = edges
            super.init(frame: .zero)
            // Clicks on fully transparent pixels fall through to the window
            // below, so the zones need a barely visible fill
            wantsLayer = true
            layer?.backgroundColor = NSColor.black.withAlphaComponent(0.002).cgColor
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override var mouseDownCanMoveWindow: Bool { false }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: cursor)
        }

        override func mouseDown(with event: NSEvent) {
            startFrame = window?.frame ?? .zero
            startMouse = NSEvent.mouseLocation
        }

        override func mouseDragged(with event: NSEvent) {
            guard let window = window else { return }
            let mouse = NSEvent.mouseLocation
            let frame = edges.resize(
                startFrame,
                dx: mouse.x - startMouse.x,
                dy: mouse.y - startMouse.y,
                minSize: window.minSize
            )
            window.setFrame(frame, display: true)
        }

        private var cursor: NSCursor {
            if #available(macOS 15.0, *), let position = frameResizePosition {
                return NSCursor.frameResize(position: position, directions: .all)
            }
            if edges == .left || edges == .right {
                return .resizeLeftRight
            }
            if edges == .top || edges == .bottom {
                return .resizeUpDown
            }
            return .crosshair
        }

        @available(macOS 15.0, *)
        private var frameResizePosition: NSCursor.FrameResizePosition? {
            switch edges {
            case .top: return .top
            case .bottom: return .bottom
            case .left: return .left
            case .right: return .right
            case [.top, .left]: return .topLeft
            case [.top, .right]: return .topRight
            case [.bottom, .left]: return .bottomLeft
            case [.bottom, .right]: return .bottomRight
            default: return nil
            }
        }
    }
}
