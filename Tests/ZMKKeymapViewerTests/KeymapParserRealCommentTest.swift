import XCTest
@testable import ZMKKeymapViewerApp

final class KeymapParserRealCommentTest: XCTestCase {
    func testParseBindingsStripsRealKeymapCommentLine() {
        let input = """
                // col 0       // col 1      // col 2        // col 3       // col 4         // col 5       // col 6             // col 7        // col 8              // col 9
&kp Q &kp W &kp F
"""
        let bindings = KeymapParser.parseBindings(from: input)
        let display = bindings.map { $0.displayText }
        XCTAssertEqual(display, ["Q", "W", "F"], "Should ignore the comment line and only parse key bindings")
    }
}
