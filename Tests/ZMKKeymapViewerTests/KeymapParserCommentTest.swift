import XCTest
@testable import ZMKKeymapViewerApp

final class KeymapParserCommentTest: XCTestCase {
    func testParseBindingsStripsCommentLines() {
        let input = """
&kp Q &kp W &kp E
// col 0 // col 1 // col 2
&kp A &kp S &kp D
"""
        let bindings = KeymapParser.parseBindings(from: input)
        let display = bindings.map { $0.displayText }
        XCTAssertEqual(display, ["Q", "W", "E", "A", "S", "D"], "Should ignore comment line and only parse key bindings")
    }
}
