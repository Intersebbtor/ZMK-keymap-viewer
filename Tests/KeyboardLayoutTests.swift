import XCTest
@testable import ZMKKeymapViewerApp

/// Tests for KeyboardLayout detection and configuration
class KeyboardLayoutTests: XCTestCase {
    
    // MARK: - Test Predefined Layouts
    
    func testSweepLayoutProperties() {
        let sweep = KeyboardLayout.sweep
        
        XCTAssertEqual(sweep.totalKeys, 34)
        XCTAssertEqual(sweep.keysPerRow, [10, 10, 10, 4])
        XCTAssertEqual(sweep.rowCount, 4)
        XCTAssertTrue(sweep.hasThumbCluster)
        XCTAssertEqual(sweep.thumbKeysCount, 4)
        XCTAssertEqual(sweep.name, "Sweep/Cradio")
    }
    
    func testCorneLayoutProperties() {
        let corne = KeyboardLayout.corne
        
        XCTAssertEqual(corne.totalKeys, 42)
        XCTAssertEqual(corne.keysPerRow, [12, 12, 12, 6])
        XCTAssertEqual(corne.rowCount, 4)
        XCTAssertTrue(corne.hasThumbCluster)
        XCTAssertEqual(corne.thumbKeysCount, 6)
        XCTAssertEqual(corne.name, "Corne")
    }
    
    // MARK: - Test Layout Detection
    
    func testDetectSweepLayout() {
        let layout = KeyboardLayout.detect(fromKeyCount: 34, keysPerRow: [10, 10, 10, 4])
        
        XCTAssertEqual(layout.totalKeys, 34)
        XCTAssertEqual(layout.name, "Sweep/Cradio")
    }
    
    func testDetectCorneLayout() {
        let layout = KeyboardLayout.detect(fromKeyCount: 42, keysPerRow: [12, 12, 12, 6])
        
        XCTAssertEqual(layout.totalKeys, 42)
        XCTAssertEqual(layout.name, "Corne")
    }
    
    func testDetectCustomLayout() {
        let layout = KeyboardLayout.detect(fromKeyCount: 50, keysPerRow: [12, 12, 12, 14])
        
        XCTAssertEqual(layout.totalKeys, 50)
        XCTAssertEqual(layout.name, "Custom (50 keys)")
        XCTAssertEqual(layout.rowCount, 4)
    }
    
    func testDetectLayoutWithFewerRows() {
        let layout = KeyboardLayout.detect(fromKeyCount: 30, keysPerRow: [10, 10, 10])
        
        XCTAssertEqual(layout.totalKeys, 30)
        XCTAssertEqual(layout.rowCount, 3)
    }
    
    func testThumbClusterDetection() {
        let layoutWithThumb = KeyboardLayout.detect(fromKeyCount: 34, keysPerRow: [10, 10, 10, 4])
        XCTAssertTrue(layoutWithThumb.hasThumbCluster)
        
        let layoutWithoutThumb = KeyboardLayout.detect(fromKeyCount: 30, keysPerRow: [10, 10, 10])
        XCTAssertFalse(layoutWithoutThumb.hasThumbCluster)
    }
    
    // MARK: - Test Layout Equality
    
    func testLayoutEquality() {
        let layout1 = KeyboardLayout.sweep
        let layout2 = KeyboardLayout.sweep
        
        XCTAssertEqual(layout1, layout2)
    }
    
    func testLayoutInequality() {
        let sweep = KeyboardLayout.sweep
        let corne = KeyboardLayout.corne
        
        XCTAssertNotEqual(sweep, corne)
    }
    
    func testCustomLayoutsWithSamePropertiesAreEqual() {
        let layout1 = KeyboardLayout(
            totalKeys: 50,
            keysPerRow: [12, 12, 12, 14],
            rowCount: 4,
            hasThumbCluster: true,
            thumbKeysCount: 14,
            name: "Custom Layout"
        )
        
        let layout2 = KeyboardLayout(
            totalKeys: 50,
            keysPerRow: [12, 12, 12, 14],
            rowCount: 4,
            hasThumbCluster: true,
            thumbKeysCount: 14,
            name: "Custom Layout"
        )
        
        XCTAssertEqual(layout1, layout2)
    }
    
    // MARK: - Test Thumb Cluster Detection
    
    func testThumbKeysCounting() {
        let layout = KeyboardLayout(
            totalKeys: 38,
            keysPerRow: [10, 10, 10, 8],
            rowCount: 4,
            hasThumbCluster: true,
            thumbKeysCount: 8,
            name: "Extended Sweep"
        )
        
        XCTAssertEqual(layout.thumbKeysCount, 8)
    }
    
    func testSmallThumbCluster() {
        let layout = KeyboardLayout.detect(fromKeyCount: 32, keysPerRow: [10, 10, 10, 2])
        
        XCTAssertTrue(layout.hasThumbCluster)
        XCTAssertEqual(layout.thumbKeysCount, 2)
    }
    
    func testLargeThumbCluster() {
        let layout = KeyboardLayout(
            totalKeys: 52,
            keysPerRow: [12, 12, 12, 16],
            rowCount: 4,
            hasThumbCluster: true,
            thumbKeysCount: 16,
            name: "Custom Large"
        )
        
        XCTAssertEqual(layout.thumbKeysCount, 16)
    }
    
    // MARK: - Test Row Configuration
    
    func testKeysPerRowArray() {
        let layout = KeyboardLayout.detect(fromKeyCount: 34, keysPerRow: [10, 10, 10, 4])
        
        XCTAssertEqual(layout.keysPerRow.count, 4)
        XCTAssertEqual(layout.keysPerRow[0], 10)
        XCTAssertEqual(layout.keysPerRow[1], 10)
        XCTAssertEqual(layout.keysPerRow[2], 10)
        XCTAssertEqual(layout.keysPerRow[3], 4)
    }
    
    func testAsymmetricalRows() {
        let layout = KeyboardLayout.detect(fromKeyCount: 44, keysPerRow: [12, 12, 12, 8])
        
        XCTAssertEqual(layout.rowCount, 4)
        let totalFromRows = layout.keysPerRow.reduce(0, +)
        XCTAssertEqual(totalFromRows, 44)
    }
    
    // MARK: - Test Edge Cases
    
    func testSingleKeyLayout() {
        let layout = KeyboardLayout(
            totalKeys: 1,
            keysPerRow: [1],
            rowCount: 1,
            hasThumbCluster: false,
            thumbKeysCount: 0,
            name: "Single Key"
        )
        
        XCTAssertEqual(layout.totalKeys, 1)
        XCTAssertEqual(layout.rowCount, 1)
    }
    
    func testLargeLayout() {
        let layout = KeyboardLayout(
            totalKeys: 100,
            keysPerRow: Array(repeating: 10, count: 10),
            rowCount: 10,
            hasThumbCluster: false,
            thumbKeysCount: 0,
            name: "Large Layout"
        )
        
        XCTAssertEqual(layout.totalKeys, 100)
        XCTAssertEqual(layout.rowCount, 10)
    }
    
    func testDetectWithZeroKeys() {
        let layout = KeyboardLayout.detect(fromKeyCount: 0, keysPerRow: [])
        
        XCTAssertEqual(layout.totalKeys, 0)
    }
}
