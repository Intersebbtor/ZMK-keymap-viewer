import XCTest
@testable import ZMKKeymapViewerApp

/// Tests for KeyboardLayout detection and configuration
class KeyboardLayoutTests: XCTestCase {

    // MARK: - Test Layout Creation

    func testSweepLayoutProperties() {
        let sweep = KeyboardLayout.create(keyCount: 34, keysPerRow: [10, 10, 10, 4], detectedName: "Sweep/Cradio")

        XCTAssertEqual(sweep.totalKeys, 34)
        XCTAssertEqual(sweep.keysPerRow, [10, 10, 10, 4])
        XCTAssertEqual(sweep.rowCount, 4)
        XCTAssertTrue(sweep.hasThumbCluster)
        XCTAssertEqual(sweep.thumbKeysCount, 4)
        XCTAssertEqual(sweep.name, "Sweep/Cradio")
        XCTAssertTrue(sweep.isSplit)
    }

    func testCorneLayoutProperties() {
        let corne = KeyboardLayout.create(keyCount: 42, keysPerRow: [12, 12, 12, 6], detectedName: "Corne")

        XCTAssertEqual(corne.totalKeys, 42)
        XCTAssertEqual(corne.keysPerRow, [12, 12, 12, 6])
        XCTAssertEqual(corne.rowCount, 4)
        XCTAssertTrue(corne.hasThumbCluster)
        XCTAssertEqual(corne.thumbKeysCount, 6)
        XCTAssertEqual(corne.name, "Corne")
    }

    func testCreateWithoutNameUsesCustomName() {
        let layout = KeyboardLayout.create(keyCount: 50, keysPerRow: [12, 12, 12, 14], detectedName: nil)

        XCTAssertEqual(layout.totalKeys, 50)
        XCTAssertEqual(layout.name, "Custom (50 keys)")
        XCTAssertEqual(layout.rowCount, 4)
    }

    func testCreateDefaultsToSplit() {
        let layout = KeyboardLayout.create(keyCount: 30, keysPerRow: [10, 10, 10], detectedName: nil)
        XCTAssertTrue(layout.isSplit)
    }

    func testCreateNonSplit() {
        let layout = KeyboardLayout.create(keyCount: 48, keysPerRow: [12, 12, 12, 12], detectedName: "Planck", isSplit: false)
        XCTAssertFalse(layout.isSplit)
    }

    func testCreateWithFewerRows() {
        let layout = KeyboardLayout.create(keyCount: 30, keysPerRow: [10, 10, 10], detectedName: nil)

        XCTAssertEqual(layout.totalKeys, 30)
        XCTAssertEqual(layout.rowCount, 3)
    }

    func testThumbClusterDetection() {
        let layoutWithThumb = KeyboardLayout.create(keyCount: 34, keysPerRow: [10, 10, 10, 4], detectedName: nil)
        XCTAssertTrue(layoutWithThumb.hasThumbCluster)

        let layoutWithoutThumb = KeyboardLayout.create(keyCount: 30, keysPerRow: [10, 10, 10], detectedName: nil)
        XCTAssertFalse(layoutWithoutThumb.hasThumbCluster)
        XCTAssertEqual(layoutWithoutThumb.thumbKeysCount, 0)
    }

    // MARK: - Test Keyboard Detection

    func testDetectKeyboardFromFilename() {
        let info = KeyboardLayout.detectKeyboardInfo(from: "", filePath: "/tmp/config/cradio.keymap")

        XCTAssertEqual(info?.name, "Sweep/Cradio")
        XCTAssertEqual(info?.isSplit, true)
    }

    func testDetectNonSplitKeyboard() {
        let info = KeyboardLayout.detectKeyboardInfo(from: "", filePath: "/tmp/config/planck.keymap")

        XCTAssertEqual(info?.name, "Planck")
        XCTAssertEqual(info?.isSplit, false)
    }

    func testDetectGo60Signature() {
        let info = KeyboardLayout.detectKeyboardInfo(from: "/* GO60 LAYOUT EDITOR */")
        XCTAssertEqual(info?.name, "Go60")
    }

    func testDetectUnknownKeyboard() {
        XCTAssertNil(KeyboardLayout.detectKeyboardInfo(from: "nothing to see here", filePath: "/tmp/my.keymap"))
    }

    // MARK: - Test Layout Equality

    func testLayoutEquality() {
        let layout1 = KeyboardLayout.create(keyCount: 34, keysPerRow: [10, 10, 10, 4], detectedName: "Sweep/Cradio")
        let layout2 = KeyboardLayout.create(keyCount: 34, keysPerRow: [10, 10, 10, 4], detectedName: "Sweep/Cradio")

        XCTAssertEqual(layout1, layout2)
    }

    func testLayoutInequality() {
        let sweep = KeyboardLayout.create(keyCount: 34, keysPerRow: [10, 10, 10, 4], detectedName: "Sweep/Cradio")
        let corne = KeyboardLayout.create(keyCount: 42, keysPerRow: [12, 12, 12, 6], detectedName: "Corne")

        XCTAssertNotEqual(sweep, corne)
    }

    func testCustomLayoutsWithSamePropertiesAreEqual() {
        let layout1 = KeyboardLayout(
            totalKeys: 50,
            keysPerRow: [12, 12, 12, 14],
            rowCount: 4,
            hasThumbCluster: true,
            thumbKeysCount: 14,
            name: "Custom Layout",
            isSplit: true
        )

        let layout2 = KeyboardLayout(
            totalKeys: 50,
            keysPerRow: [12, 12, 12, 14],
            rowCount: 4,
            hasThumbCluster: true,
            thumbKeysCount: 14,
            name: "Custom Layout",
            isSplit: true
        )

        XCTAssertEqual(layout1, layout2)
    }

    // MARK: - Test Thumb Cluster Detection

    func testSmallThumbCluster() {
        let layout = KeyboardLayout.create(keyCount: 32, keysPerRow: [10, 10, 10, 2], detectedName: nil)

        XCTAssertTrue(layout.hasThumbCluster)
        XCTAssertEqual(layout.thumbKeysCount, 2)
    }

    // MARK: - Test Row Configuration

    func testKeysPerRowArray() {
        let layout = KeyboardLayout.create(keyCount: 34, keysPerRow: [10, 10, 10, 4], detectedName: nil)

        XCTAssertEqual(layout.keysPerRow, [10, 10, 10, 4])
    }

    func testAsymmetricalRows() {
        let layout = KeyboardLayout.create(keyCount: 44, keysPerRow: [12, 12, 12, 8], detectedName: nil)

        XCTAssertEqual(layout.rowCount, 4)
        XCTAssertEqual(layout.keysPerRow.reduce(0, +), 44)
    }

    // MARK: - Test Edge Cases

    func testCreateWithZeroKeys() {
        let layout = KeyboardLayout.create(keyCount: 0, keysPerRow: [], detectedName: nil)

        XCTAssertEqual(layout.totalKeys, 0)
        XCTAssertEqual(layout.rowCount, 0)
        XCTAssertFalse(layout.hasThumbCluster)
    }
}
