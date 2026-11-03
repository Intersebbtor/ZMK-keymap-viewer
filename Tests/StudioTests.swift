import XCTest
@testable import ZMKKeymapViewerApp

/// Tests for reading the keymap from the keyboard over ZMK Studio RPC
class StudioTests: XCTestCase {

    private func bytes(_ hex: String) -> [UInt8] {
        stride(from: 0, to: hex.count, by: 2).map { offset in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            return UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)!
        }
    }

    // MARK: - HID tunnel

    func testTunnelSplitsIntoThirtyBytePayloads() {
        let reports = StudioHIDTunnel.reports(for: Array(0..<45))

        XCTAssertEqual(reports.count, 2)
        XCTAssertTrue(reports.allSatisfy { $0.count == 32 && $0[0] == 0xF2 })
        XCTAssertEqual(reports[0][1], 30)
        XCTAssertEqual(reports[1][1], 15)
        XCTAssertEqual(StudioHIDTunnel.payload(of: reports[1]), Array(30..<45))
    }

    func testTunnelIgnoresOtherReports() {
        XCTAssertNil(StudioHIDTunnel.payload(of: [0xFF, 0x04, 0x01]))
    }

    // MARK: - Framing

    func testFramingEscapesControlBytes() {
        XCTAssertEqual(StudioFraming.frame([0x01, 0xAB, 0xAC, 0xAD]), [0xAB, 0x01, 0xAC, 0xAB, 0xAC, 0xAC, 0xAC, 0xAD, 0xAD])
    }

    func testFramingRoundTripAcrossChunks() {
        let message: [UInt8] = [0x0A, 0xAB, 0x00, 0xAD, 0xAC, 0x42]
        let framed = StudioFraming.frame(message) + StudioFraming.frame([0x07])
        var decoder = StudioFraming.Decoder()

        // Byte by byte, as if every byte came in its own report
        let messages = framed.flatMap { decoder.feed([$0]) }

        XCTAssertEqual(messages, [message, [0x07]])
    }

    func testFramingDropsBrokenFrame() {
        var decoder = StudioFraming.Decoder()
        XCTAssertEqual(decoder.feed([0xAB, 0x01, 0xAB, 0x02, 0xAD]), [[0x02]])
    }

    // MARK: - Protobuf

    func testRequestEncoding() {
        // zmk.studio.Request { request_id: 2, core { get_lock_state: true } }
        XCTAssertEqual(StudioRequest.getLockState.encoded(requestID: 2), [0x08, 0x02, 0x1A, 0x02, 0x10, 0x01])
        // keymap { get_physical_layouts: true }
        XCTAssertEqual(StudioRequest.getPhysicalLayouts.encoded(requestID: 1), [0x08, 0x01, 0x2A, 0x02, 0x30, 0x01])
        // behaviors { get_behavior_details { behavior_id: 300 } }
        XCTAssertEqual(StudioRequest.getBehaviorDetails(id: 300).encoded(requestID: 1), [0x08, 0x01, 0x22, 0x05, 0x12, 0x03, 0x08, 0xAC, 0x02])
    }

    func testZigzagRoundTrip() throws {
        var writer = ProtoWriter()
        writer.sint32(1, -150)
        writer.sint32(2, 150)
        let message = try ProtoMessage(writer.bytes)

        XCTAssertEqual(message.sint32(1), -150)
        XCTAssertEqual(message.sint32(2), 150)
    }

    func testRejectsTruncatedMessage() {
        XCTAssertThrowsError(try ProtoMessage([0x0A, 0x05, 0x01]))
    }

    // MARK: - Recorded from a Sweep (serial number zeroed)

    func testDecodesRecordedDeviceInfo() throws {
        let response = try StudioResponse.decode(bytes("0a1708011a130a110a05627230306d12080000000000000000"))
        XCTAssertEqual(response, .requestResponse(id: 1, .deviceInfo(name: "br00m")))
    }

    func testDecodesRecordedLockState() throws {
        let response = try StudioResponse.decode(bytes("0a0608021a021000"))
        XCTAssertEqual(response, .requestResponse(id: 2, .lockState(.locked)))
    }

    func testDecodesUnlockNotification() throws {
        // zmk.studio.Response { notification { core { lock_state_changed: UNLOCKED } } }
        var writer = ProtoWriter()
        writer.message(2) { notification in
            notification.message(2) { $0.varint(1, 1) }
        }
        XCTAssertEqual(try StudioResponse.decode(writer.bytes), .notification(lockState: .unlocked))
    }

    // MARK: - Client against a fake keyboard

    @MainActor
    func testFetchesSnapshotFromFakeKeyboard() async throws {
        let keyboard = FakeStudioKeyboard.sweep()
        let client = keyboard.connectedClient()

        let snapshot = try await client.fetchSnapshot()

        XCTAssertEqual(snapshot.deviceName, "br00m")
        XCTAssertEqual(snapshot.layers.map(\.name), ["Base", "Num"])
        XCTAssertEqual(snapshot.layers[0].bindings.count, 34)
        XCTAssertEqual(snapshot.layout?.keys.count, 34)
        XCTAssertEqual(snapshot.behaviors[FakeStudioKeyboard.longMT]?.displayName, "long_MT")
        XCTAssertEqual(snapshot.behaviors[FakeStudioKeyboard.longMT]?.param1, .hidUsage)
        // Unused behaviors are not fetched
        XCTAssertNil(snapshot.behaviors[FakeStudioKeyboard.unused])
    }

    @MainActor
    func testLockedKeyboardThrowsLocked() async {
        let keyboard = FakeStudioKeyboard.sweep()
        keyboard.unlocked = false
        let client = keyboard.connectedClient()

        do {
            _ = try await client.fetchSnapshot()
            XCTFail("expected locked")
        } catch {
            XCTAssertEqual(error as? StudioError, .locked)
        }
    }

    @MainActor
    func testUnansweredRequestTimesOut() async {
        let client = StudioClient { _ in true }
        let start = Date()

        do {
            _ = try await client.call(.getLockState)
            XCTFail("expected timeout")
        } catch {
            XCTAssertEqual(error as? StudioError, .timeout)
            XCTAssertLessThan(Date().timeIntervalSince(start), StudioClient.timeout + 1)
        }
    }

    @MainActor
    func testCancelFailsPendingRequest() async {
        let client = StudioClient { _ in true }
        Task { @MainActor in client.cancel() }

        do {
            _ = try await client.call(.getKeymap)
            XCTFail("expected notConnected")
        } catch {
            XCTAssertEqual(error as? StudioError, .notConnected)
        }
    }

    // MARK: - Converting to the viewer's keymap

    func testBindingCodes() {
        let kp = StudioBehavior(id: 1, displayName: "Key Press", param1: .hidUsage, param2: .none)
        let mt = StudioBehavior(id: 2, displayName: "Mod-Tap", param1: .hidUsage, param2: .hidUsage)
        let lt = StudioBehavior(id: 3, displayName: "Layer-Tap", param1: .layer, param2: .hidUsage)
        let bt = StudioBehavior(id: 4, displayName: "Bluetooth", param1: .number, param2: .number)
        let macro = StudioBehavior(id: 5, displayName: "dqt_a", param1: .none, param2: .none)

        func code(_ behavior: StudioBehavior, _ p1: UInt32, _ p2: UInt32 = 0) -> String {
            StudioKeymapConverter.bindingCode(StudioBinding(behaviorID: Int32(behavior.id), param1: p1, param2: p2), behavior: behavior)
        }

        XCTAssertEqual(code(kp, 0x07_0014), "&kp Q")
        XCTAssertEqual(code(kp, 0x0207_001E), "&kp EXCL", "shift + 1 is written as the symbol")
        XCTAssertEqual(code(kp, 0x0A07_0021), "&kp LS(LG(N4))", "shift with other modifiers is a shortcut")
        XCTAssertEqual(code(kp, 0x0D07_0006), "&kp LC(LA(LG(C)))", "modifiers in the macOS order ⌃⌥⇧⌘")
        XCTAssertEqual(code(kp, 0x07_0081), "&kp K_VOLUME_DOWN")
        XCTAssertEqual(code(kp, 0x0C_00E9), "&kp C_VOL_UP")
        XCTAssertEqual(code(mt, 0x07_00E1, 0x07_001D), "&mt LSHFT Z")
        XCTAssertEqual(code(lt, 2, 0x07_002C), "&lt 2 SPACE")
        XCTAssertEqual(code(bt, 3, 1), "&bt BT_SEL 1")
        XCTAssertEqual(code(macro, 0), "&dqt_a")
        XCTAssertEqual(StudioKeymapConverter.bindingCode(StudioBinding(behaviorID: 99, param1: 0, param2: 0), behavior: nil), "&none")
    }

    func testRowsFollowPhysicalLayout() {
        let layout = FakeStudioKeyboard.sweepLayout()
        let rows = StudioKeymapConverter.rowLengths(of: layout, keyCount: 34)

        XCTAssertEqual(rows, [10, 10, 10, 4])
        XCTAssertTrue(StudioKeymapConverter.isSplit(layout, rows: rows))
    }

    func testRowsWithoutPhysicalLayout() {
        XCTAssertEqual(StudioKeymapConverter.rowLengths(of: nil, keyCount: 24), [10, 10, 4])
    }

    @MainActor
    func testConvertsSnapshotToKeymap() async throws {
        let snapshot = try await FakeStudioKeyboard.sweep().connectedClient().fetchSnapshot()

        let keymap = try XCTUnwrap(StudioKeymapConverter.keymap(from: snapshot))

        XCTAssertEqual(keymap.layout.keysPerRow, [10, 10, 10, 4])
        XCTAssertEqual(keymap.layout.name, "br00m")
        XCTAssertTrue(keymap.layout.hasThumbCluster)
        let base = keymap.layers[0].bindings
        XCTAssertEqual(base[0].rawCode, "&long_MT RCTRL Q")
        XCTAssertEqual(base[0].displayText, "⌃\nQ")
        XCTAssertEqual(base[20].rawCode, "&mt LSHFT Z")
        XCTAssertEqual(base[31].displayText, "L2\n⌫")
        XCTAssertEqual(base[33].displayText, "!")
        XCTAssertEqual(base[30].row, 3, "thumb keys get their own row")
        XCTAssertEqual(keymap.layers[1].bindings[0].rawCode, "&bt BT_SEL 1")
        XCTAssertEqual(keymap.layers[1].bindings[5].displayText, "▽")
    }

    @MainActor
    func testAliasesFromFileAreKept() async throws {
        let snapshot = try await FakeStudioKeyboard.sweep().connectedClient().fetchSnapshot()
        var aliases = Array(repeating: [String?](repeating: nil, count: 34), count: 2)
        aliases[0][33] = "Bang"

        let keymap = try XCTUnwrap(StudioKeymapConverter.keymap(from: snapshot, aliases: aliases))

        XCTAssertEqual(keymap.layers[0].bindings[33].effectiveDisplayText, "Bang")
        XCTAssertNil(keymap.layers[0].bindings[32].alias)
    }

    @MainActor
    func testViewModelPrefersKeyboardAndFallsBack() async throws {
        let snapshot = try await FakeStudioKeyboard.sweep().connectedClient().fetchSnapshot()
        let viewModel = KeymapViewModel()

        viewModel.applyKeyboardSnapshot(snapshot)
        XCTAssertEqual(viewModel.keyboardKeymapName, "br00m")
        XCTAssertEqual(viewModel.keymap?.layers.count, 2)

        viewModel.applyKeyboardSnapshot(nil)
        XCTAssertNil(viewModel.keyboardKeymapName)
        XCTAssertNil(viewModel.keymap, "no file loaded, nothing to fall back to")
    }

    @MainActor
    func testKeyboardLayerNamesFallBackToFile() async throws {
        let keyboard = FakeStudioKeyboard.sweep()
        let unnamed = FakeStudioKeyboard(
            layers: keyboard.layers.map { StudioLayer(id: $0.id, name: "", bindings: $0.bindings) },
            layout: keyboard.layout,
            behaviors: keyboard.behaviors
        )
        let snapshot = try await unnamed.connectedClient().fetchSnapshot()

        let keymap = try XCTUnwrap(StudioKeymapConverter.keymap(from: snapshot, fallbackLayerNames: ["Base"]))

        XCTAssertEqual(keymap.layers.map(\.name), ["Base", "Layer 1"])
    }

    // MARK: - Recorded from a real keyboard

    /// Decodes the recorded responses in the order the client asked for them
    private func recordedSweepSnapshot() throws -> StudioSnapshot {
        var name = ""
        var layers: [StudioLayer] = []
        var layout: StudioPhysicalLayout?
        var behaviors: [UInt32: StudioBehavior] = [:]
        for line in StudioFixtures.sweepSnapshot.split(separator: "\n") {
            guard case let .requestResponse(_, result) = try StudioResponse.decode(bytes(String(line))) else { continue }
            switch result {
            case let .deviceInfo(deviceName): name = deviceName
            case let .keymap(recorded): layers = recorded
            case let .physicalLayouts(active, layouts): layout = layouts[active]
            case let .behavior(behavior): behaviors[behavior.id] = behavior
            default: break
            }
        }
        return StudioSnapshot(deviceName: name, layers: layers, layout: layout, behaviors: behaviors)
    }

    func testRealSweepSnapshot() throws {
        let keymap = try XCTUnwrap(StudioKeymapConverter.keymap(from: try recordedSweepSnapshot()))

        XCTAssertEqual(keymap.layout.name, "br00m")
        XCTAssertEqual(keymap.layout.keysPerRow, [10, 10, 10, 4])
        XCTAssertTrue(keymap.layout.isSplit)
        XCTAssertEqual(keymap.layers.map(\.name), ["Base", "Num,Arrow", "Sym,Nav,CTRL", "Magnet,Arc", "BT Control"])
        XCTAssertTrue(keymap.layers.allSatisfy { $0.bindings.count == 34 })
    }

    func testRealSweepLabelsMatchTheKeymapFile() throws {
        let layers = try XCTUnwrap(StudioKeymapConverter.keymap(from: try recordedSweepSnapshot())).layers

        func label(_ layer: Int, _ position: Int) -> String { layers[layer].bindings[position].displayText }
        func fileLabel(_ code: String) -> String { KeymapParser.parseBindings(from: code)[0].displayText }

        // Custom hold-taps come back by their label, LONG_MT for &long_MT
        XCTAssertEqual(label(0, 0), fileLabel("&long_MT RIGHT_CONTROL Q"))
        XCTAssertEqual(label(0, 33), fileLabel("&short_LT 2 TAB"))
        XCTAssertEqual(label(0, 31), fileLabel("&lt 1 BACKSPACE"))
        XCTAssertEqual(label(1, 21), "VOL-")
        XCTAssertEqual(label(1, 22), "VOL+")
        XCTAssertEqual(label(1, 23), fileLabel("&kp LS(LG(NUMBER_4))"), "a shortcut, not ⌘+$")
        XCTAssertEqual(label(2, 0), "!")
        XCTAssertEqual(label(3, 5), fileLabel("&kp LC(LA(LEFT))"), "modifiers in the macOS order")
        XCTAssertEqual(label(4, 9), fileLabel("&studio_unlock"))
        XCTAssertEqual(label(4, 15), fileLabel("&bt BT_SEL 0"))
        XCTAssertEqual(label(1, 24), "⌃+⌥+⇧+⌘+1")
    }
}

// MARK: - Fake keyboard

/// Answers ZMK Studio requests like the firmware does, per zmk-studio-messages
final class FakeStudioKeyboard {
    static let keyPress: UInt32 = 1
    static let modTap: UInt32 = 2
    static let layerTap: UInt32 = 3
    static let momentary: UInt32 = 4
    static let transparent: UInt32 = 5
    static let bluetooth: UInt32 = 6
    static let longMT: UInt32 = 7
    static let unused: UInt32 = 8

    var unlocked = true
    let layers: [StudioLayer]
    let layout: StudioPhysicalLayout
    let behaviors: [(id: UInt32, name: String, param1: Int?, param2: Int?)]

    init(layers: [StudioLayer], layout: StudioPhysicalLayout, behaviors: [(id: UInt32, name: String, param1: Int?, param2: Int?)]) {
        self.layers = layers
        self.layout = layout
        self.behaviors = behaviors
    }

    /// Value type field numbers of BehaviorParameterValueDescription
    private static let hid = 5
    private static let layer = 6
    private static let constant = 3

    static func sweep() -> FakeStudioKeyboard {
        func kp(_ usage: UInt32) -> StudioBinding { StudioBinding(behaviorID: Int32(keyPress), param1: usage, param2: 0) }
        let letters: [UInt32] = [
            0x14, 0x1A, 0x08, 0x15, 0x17, 0x1C, 0x18, 0x0C, 0x12, 0x13,  // Q W E R T Y U I O P
            0x04, 0x16, 0x07, 0x09, 0x0A, 0x0B, 0x0D, 0x0E, 0x0F, 0x33,  // A S D F G H J K L ;
            0x1D, 0x1B, 0x06, 0x19, 0x05, 0x11, 0x10, 0x36, 0x37, 0x38,  // Z X C V B N M , . /
        ]
        var base = letters.map { kp(0x07_0000 | $0) }
        base[0] = StudioBinding(behaviorID: Int32(longMT), param1: 0x07_00E4, param2: 0x07_0014)
        base[20] = StudioBinding(behaviorID: Int32(modTap), param1: 0x07_00E1, param2: 0x07_001D)
        base += [
            StudioBinding(behaviorID: Int32(momentary), param1: 1, param2: 0),
            StudioBinding(behaviorID: Int32(layerTap), param1: 2, param2: 0x07_002A),
            StudioBinding(behaviorID: Int32(layerTap), param1: 3, param2: 0x07_002C),
            kp(0x0207_001E),
        ]

        var num = Array(repeating: StudioBinding(behaviorID: Int32(transparent), param1: 0, param2: 0), count: 34)
        num[0] = StudioBinding(behaviorID: Int32(bluetooth), param1: 3, param2: 1)

        return FakeStudioKeyboard(
            layers: [StudioLayer(id: 0, name: "Base", bindings: base), StudioLayer(id: 1, name: "Num", bindings: num)],
            layout: sweepLayout(),
            behaviors: [
                (keyPress, "Key Press", hid, nil),
                (modTap, "Mod-Tap", hid, hid),
                (layerTap, "Layer-Tap", layer, hid),
                (momentary, "Momentary Layer", layer, nil),
                (transparent, "Transparent", nil, nil),
                (bluetooth, "Bluetooth", constant, constant),
                (longMT, "long_MT", hid, hid),
                (unused, "Caps Word", nil, nil),
            ]
        )
    }

    /// Column-staggered 3×5 per half with the right half 2u away, plus 2 thumbs per half
    static func sweepLayout() -> StudioPhysicalLayout {
        let stagger: [Int32] = [50, 25, 0, 25, 40]
        var keys: [StudioKeyAttributes] = []
        for row in 0..<3 {
            for column in 0..<10 {
                let x = Int32(column) * 100 + (column >= 5 ? 200 : 0)
                let y = Int32(row) * 100 + stagger[column < 5 ? column : 9 - column]
                keys.append(StudioKeyAttributes(width: 100, height: 100, x: x, y: y))
            }
        }
        for x: Int32 in [300, 400, 700, 800] {
            keys.append(StudioKeyAttributes(width: 100, height: 100, x: x, y: 350))
        }
        return StudioPhysicalLayout(name: "Default", keys: keys)
    }

    /// A client whose reports reach this keyboard and whose responses come back
    /// asynchronously, like input reports
    @MainActor
    func connectedClient() -> StudioClient {
        let box = ClientBox()
        var decoder = StudioFraming.Decoder()
        box.client = StudioClient { [self] report in
            guard let payload = StudioHIDTunnel.payload(of: report) else { return false }
            for message in decoder.feed(payload) {
                let reports = StudioHIDTunnel.reports(for: StudioFraming.frame(respond(to: message)))
                Task { @MainActor in
                    reports.forEach { box.client?.receive(StudioHIDTunnel.payload(of: $0)!) }
                }
            }
            return true
        }
        return box.client!
    }

    private final class ClientBox {
        var client: StudioClient?
    }

    func respond(to requestBytes: [UInt8]) -> [UInt8] {
        let request = try! ProtoMessage(requestBytes)
        let id = request.uint(1)
        var writer = ProtoWriter()
        writer.message(1) { response in
            response.varint(1, id)
            if let core = try! request.message(3) {
                response.message(3) { reply in
                    if core.has(1) {
                        reply.message(1) { info in
                            info.string(1, "br00m")
                            info.bytes(2, [0, 0, 0, 0])
                        }
                    } else {
                        reply.varint(2, unlocked ? 1 : 0)
                    }
                }
            } else if !unlocked {
                response.message(2) { $0.varint(2, 1) }  // UNLOCK_REQUIRED
            } else if let keymap = try! request.message(5) {
                response.message(5) { reply in
                    if keymap.has(1) {
                        reply.message(1) { encodeKeymap(&$0) }
                    } else {
                        reply.message(6) { encodeLayouts(&$0) }
                    }
                }
            } else if let behaviorRequest = try! request.message(4) {
                response.message(4) { reply in
                    if let details = try! behaviorRequest.message(2) {
                        reply.message(2) { encodeBehavior(details.uint32(1), &$0) }
                    } else {
                        reply.message(1) { list in
                            // Packed repeated field: the varints without their tags
                            list.bytes(1, packedVarints(behaviors.map { UInt64($0.id) }))
                        }
                    }
                }
            }
        }
        return writer.bytes
    }

    private func packedVarints(_ values: [UInt64]) -> [UInt8] {
        values.flatMap { value -> [UInt8] in
            var value = value
            var out: [UInt8] = []
            while value >= 0x80 {
                out.append(UInt8(value & 0x7F) | 0x80)
                value >>= 7
            }
            out.append(UInt8(value))
            return out
        }
    }

    private func encodeKeymap(_ writer: inout ProtoWriter) {
        for layer in layers {
            writer.message(1) { message in
                message.varint(1, UInt64(layer.id))
                message.string(2, layer.name)
                for binding in layer.bindings {
                    message.message(3) { b in
                        b.sint32(1, binding.behaviorID)
                        b.varint(2, UInt64(binding.param1))
                        b.varint(3, UInt64(binding.param2))
                    }
                }
            }
        }
        writer.varint(2, 10)
        writer.varint(3, 20)
    }

    private func encodeLayouts(_ writer: inout ProtoWriter) {
        writer.varint(1, 0)
        writer.message(2) { message in
            message.string(1, layout.name)
            for key in layout.keys {
                message.message(2) { k in
                    k.sint32(1, key.width)
                    k.sint32(2, key.height)
                    k.sint32(3, key.x)
                    k.sint32(4, key.y)
                }
            }
        }
    }

    private func encodeBehavior(_ id: UInt32, _ writer: inout ProtoWriter) {
        guard let behavior = behaviors.first(where: { $0.id == id }) else { return }
        writer.varint(1, UInt64(id))
        writer.string(2, behavior.name)
        writer.message(3) { set in
            for (field, kind) in [(1, behavior.param1), (2, behavior.param2)] {
                guard let kind = kind else { continue }
                set.message(field) { description in
                    description.string(1, "param")
                    if kind == FakeStudioKeyboard.constant {
                        description.varint(kind, 1)
                    } else {
                        description.message(kind) { _ in }
                    }
                }
            }
        }
    }
}
