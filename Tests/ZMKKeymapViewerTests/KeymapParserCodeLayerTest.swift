import XCTest
@testable import ZMKKeymapViewerApp

final class KeymapParserCodeLayerTest: XCTestCase {
    func testParseBindingsHandlesCodeLayer() {
        let input = """
                &kp N1           &kp N2     &kp N3     &kp N4    &kp N5       &kp N6  &kp N7    &kp N8            &kp N9             &kp N0
                &hml LALT GRAVE  &kp LSHFT  &kp LCTRL  &kp LCMD  &none        &none   &kp RCMD  &hmr RCTRL SEMI   &hmr RSHFT MINUS   &hmr RALT EQUAL 
                &none            &none      &none      &none     &kp CAPS     &none   &none     &kp LEFT_BRACKET  &kp RIGHT_BRACKET  &kp BACKSLASH
                                    &trans      &trans    &trans     &trans       &trans  &trans
        """
        let bindings = KeymapParser.parseBindings(from: input)
        let display = bindings.map { $0.displayText }
        // Should parse all key bindings, not skip any valid lines
        XCTAssertTrue(display.contains("1"), "Should contain 1")
        XCTAssertTrue(display.contains("RCMD"), "Should contain RCMD")
        XCTAssertTrue(display.contains("["), "Should contain [")
        XCTAssertTrue(display.contains("▽"), "Should contain ▽")
        XCTAssertEqual(bindings.count, 36, "Should parse 36 keys for code_layer")
    }
}
