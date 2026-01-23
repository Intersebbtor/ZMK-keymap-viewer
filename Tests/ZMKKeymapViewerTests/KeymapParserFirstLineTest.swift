import XCTest
@testable import ZMKKeymapViewerApp

final class KeymapParserFirstLineTest: XCTestCase {
    func testFirstLineOfBindingsIsNotSkipped() {
        let input = """
&kp N1 &kp N2 &kp N3
&kp N4 &kp N5 &kp N6
"""
        let bindings = KeymapParser.parseBindings(from: input)
        let display = bindings.map { $0.displayText }
        XCTAssertEqual(display, ["N1", "N2", "N3", "N4", "N5", "N6"], "Should include all keys, including the first line")
    }
    func testFirstLineWithCommentAbove() {
        let input = """
// comment
&kp N1 &kp N2 &kp N3
&kp N4 &kp N5 &kp N6
"""
        let bindings = KeymapParser.parseBindings(from: input)
        let display = bindings.map { $0.displayText }
        XCTAssertEqual(display, ["N1", "N2", "N3", "N4", "N5", "N6"], "Should include all keys, even with a comment above")
    }
}
