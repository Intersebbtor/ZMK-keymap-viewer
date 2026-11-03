import XCTest
@testable import ZMKKeymapViewerApp

/// Tests for decoding live layer packets and choosing the displayed layer
class LiveLayerTests: XCTestCase {

    // MARK: - Packet Decoding

    /// A 32-byte report as zmk-raw-hid sends it, zero padded
    private func report(_ prefix: [UInt8]) -> [UInt8] {
        prefix + Array(repeating: 0, count: 32 - prefix.count)
    }

    func testDecodeLayerState() {
        // default = layer 0, active = layers 0 and 2
        let bytes = report([0xFF, 0x04, 0x01, 0x00, 0x00, 0x00, 0x05, 0x00, 0x00, 0x00])

        XCTAssertEqual(LayerPacket.decode(bytes), .layerState(defaultLayers: 0x1, activeLayers: 0x5))
    }

    func testDecodeLayerStateIsLittleEndian() {
        let bytes = report([0xFF, 0x04, 0x01, 0x00, 0x00, 0x00, 0x01, 0x01, 0x00, 0x80])

        XCTAssertEqual(LayerPacket.decode(bytes), .layerState(defaultLayers: 0x1, activeLayers: 0x8000_0101))
    }

    func testDecodeKeyEvent() {
        XCTAssertEqual(LayerPacket.decode(report([0xF1, 0x00, 14, 1])), .keyEvent(position: 14, pressed: true))
        XCTAssertEqual(LayerPacket.decode(report([0xF1, 0x00, 14, 0])), .keyEvent(position: 14, pressed: false))
    }

    func testIgnoresStudioRpcAndUnknownPackets() {
        XCTAssertNil(LayerPacket.decode(report([0xF2, 0x10, 0xAB])))
        XCTAssertNil(LayerPacket.decode(report([0x00])))
    }

    func testIgnoresTruncatedPackets() {
        XCTAssertNil(LayerPacket.decode([]))
        XCTAssertNil(LayerPacket.decode([0xFF, 0x04, 0x01, 0x00, 0x00, 0x00, 0x05]))
        XCTAssertNil(LayerPacket.decode([0xF1, 0x00, 14]))
    }

    // MARK: - Highest Layer

    func testHighestLayerOnBase() {
        XCTAssertEqual(ActiveLayerResolver.highestLayer(activeLayers: 0x1, defaultLayers: 0x1), 0)
    }

    func testHighestLayerPicksTopOfStack() {
        XCTAssertEqual(ActiveLayerResolver.highestLayer(activeLayers: 0b1011, defaultLayers: 0x1), 3)
    }

    func testHighestLayerTreatsEmptyMaskAsBase() {
        XCTAssertEqual(ActiveLayerResolver.highestLayer(activeLayers: 0, defaultLayers: 0), 0)
    }

    func testHighestLayerUsesAllBits() {
        XCTAssertEqual(ActiveLayerResolver.highestLayer(activeLayers: 0x8000_0001, defaultLayers: 0x1), 31)
    }

    // MARK: - Key Positions

    func testKeyPositionIsIndexInSourceOrder() {
        let bindings = KeymapParser.parseBindings(from: """
        &kp Q &kp W &kp E
        &kp A &kp S
        """)
        let layer = KeymapLayer(name: "Base", bindings: bindings, rowCount: 2, columnCount: 3)

        XCTAssertEqual(layer.position(of: bindings[0]), 0)
        XCTAssertEqual(layer.position(of: bindings[3]), 3)
        XCTAssertEqual(bindings[3].row, 1)
    }

    func testPressedKeysAreTrackedAndClearedOnDisconnect() {
        let viewModel = KeymapViewModel()
        viewModel.setKey(position: 3, pressed: true)
        viewModel.setKey(position: 7, pressed: true)
        viewModel.setKey(position: 3, pressed: false)
        XCTAssertEqual(viewModel.pressedPositions, [7])

        viewModel.clearLiveLayer()
        XCTAssertTrue(viewModel.pressedPositions.isEmpty)
    }

    // MARK: - Window Resizing

    private let frame = NSRect(x: 100, y: 100, width: 400, height: 200)
    private let minSize = NSSize(width: 280, height: 140)

    func testResizeRightAndTopKeepOrigin() {
        let result = ResizeEdges([.top, .right]).resize(frame, dx: 50, dy: 30, minSize: minSize)
        XCTAssertEqual(result, NSRect(x: 100, y: 100, width: 450, height: 230))
    }

    func testResizeLeftAndBottomKeepOppositeEdges() {
        let result = ResizeEdges([.bottom, .left]).resize(frame, dx: -50, dy: -30, minSize: minSize)
        XCTAssertEqual(result, NSRect(x: 50, y: 70, width: 450, height: 230))
    }

    func testResizeSingleEdgeLeavesOtherAxis() {
        let result = ResizeEdges.left.resize(frame, dx: 20, dy: 99, minSize: minSize)
        XCTAssertEqual(result, NSRect(x: 120, y: 100, width: 380, height: 200))
    }

    func testResizeRespectsMinSize() {
        let result = ResizeEdges([.bottom, .left]).resize(frame, dx: 500, dy: 500, minSize: minSize)
        XCTAssertEqual(result, NSRect(x: 220, y: 160, width: 280, height: 140))
    }

    // MARK: - Menu Bar Symbol

    func testMenuBarShowsZeroOnBaseLayer() {
        XCTAssertEqual(MenuBarSymbol.name(liveIndex: 0, showLayer: true), "0.square.fill")
    }

    func testMenuBarShowsLayerNumber() {
        XCTAssertEqual(MenuBarSymbol.name(liveIndex: 3, showLayer: true), "3.square.fill")
    }

    func testMenuBarShowsKeyboardWithoutLiveLayer() {
        XCTAssertEqual(MenuBarSymbol.name(liveIndex: nil, showLayer: true), "keyboard")
    }

    func testMenuBarShowsKeyboardWhenDisabled() {
        XCTAssertEqual(MenuBarSymbol.name(liveIndex: 3, showLayer: false), "keyboard")
    }

    func testMenuBarShowsKeyboardBeyondNumberedSymbols() {
        XCTAssertEqual(MenuBarSymbol.name(liveIndex: 50, showLayer: true), "50.square.fill")
        XCTAssertEqual(MenuBarSymbol.name(liveIndex: 51, showLayer: true), "keyboard")
    }

    // MARK: - Layer Selection

    func testLiveLayerIsDisplayedWhenFollowing() {
        var selection = LayerSelection()
        selection.applyLive(2, layerCount: 5, follow: true)

        XCTAssertEqual(selection.displayedIndex, 2)
        XCTAssertEqual(selection.liveIndex, 2)
    }

    func testLiveLayerIsNotDisplayedWhenNotFollowing() {
        var selection = LayerSelection()
        selection.selectManually(1)
        selection.applyLive(3, layerCount: 5, follow: false)

        XCTAssertEqual(selection.displayedIndex, 1)
        XCTAssertEqual(selection.liveIndex, 3)
    }

    func testManualSelectionHoldsUntilNextLiveChange() {
        var selection = LayerSelection()
        selection.applyLive(2, layerCount: 5, follow: true)
        selection.selectManually(4)
        XCTAssertEqual(selection.displayedIndex, 4)

        selection.applyLive(0, layerCount: 5, follow: true)
        XCTAssertEqual(selection.displayedIndex, 0)
    }

    func testUnknownLiveLayerKeepsDisplayedLayer() {
        var selection = LayerSelection()
        selection.applyLive(1, layerCount: 3, follow: true)
        selection.applyLive(6, layerCount: 3, follow: true)

        XCTAssertEqual(selection.displayedIndex, 1)
        XCTAssertEqual(selection.liveIndex, 6)
    }

    func testClearLiveKeepsDisplayedLayer() {
        var selection = LayerSelection()
        selection.applyLive(2, layerCount: 5, follow: true)
        selection.clearLive()

        XCTAssertNil(selection.liveIndex)
        XCTAssertEqual(selection.displayedIndex, 2)
    }

    func testResetStartsOnLiveLayer() {
        var selection = LayerSelection()
        selection.applyLive(3, layerCount: 0, follow: true)
        selection.reset(layerCount: 5)

        XCTAssertEqual(selection.displayedIndex, 3)
    }

    func testResetFallsBackToBase() {
        var selection = LayerSelection()
        selection.selectManually(4)
        selection.reset(layerCount: 5)
        XCTAssertEqual(selection.displayedIndex, 0)

        selection.applyLive(7, layerCount: 5, follow: true)
        selection.reset(layerCount: 5)
        XCTAssertEqual(selection.displayedIndex, 0)
    }

    func testClampAfterLayersWereRemoved() {
        var selection = LayerSelection()
        selection.selectManually(4)

        selection.clamp(layerCount: 5)
        XCTAssertEqual(selection.displayedIndex, 4)

        selection.clamp(layerCount: 3)
        XCTAssertEqual(selection.displayedIndex, 2)

        selection.clamp(layerCount: 0)
        XCTAssertEqual(selection.displayedIndex, 0)
    }
}
