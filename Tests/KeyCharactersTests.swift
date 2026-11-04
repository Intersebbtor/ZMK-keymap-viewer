import XCTest
@testable import ZMKKeymapViewerApp

/// Labels showing what a key types, from a layout given by the test
class KeyCharactersTests: XCTestCase {

    private func combo(_ keyCode: UInt16, shift: Bool = false, option: Bool = false) -> KeyCharacters.Combo {
        KeyCharacters.Combo(keyCode: keyCode, shift: shift, option: option)
    }

    override func setUp() {
        super.setUp()
        // A few keys of the ABC layout, plus German ones on SEMI and MINUS
        KeyCharacters.table = [
            combo(0x0C): "q",
            combo(0x13): "2",
            combo(0x12, shift: true): "!",
            combo(0x13, shift: true, option: true): "€",
            combo(0x01, option: true): "ß",
            combo(0x20, option: true): "¨",
            combo(0x29): "ö",
            combo(0x1B): "ß",
        ]
    }

    override func tearDown() {
        KeyCharacters.table = [:]
        super.tearDown()
    }

    func testOptionCombosShowTheirCharacter() {
        XCTAssertEqual(KeyCharacters.typedCharacter(for: "LS(LA(N2))"), "€")
        XCTAssertEqual(KeyCharacters.typedCharacter(for: "LA(LS(NUMBER_2))"), "€", "nesting order doesn't matter")
        XCTAssertEqual(KeyCharacters.typedCharacter(for: "RA(S)"), "ß")
        XCTAssertEqual(KeyCharacters.typedCharacter(for: "LA(U)"), "¨", "a dead key shows its mark")
    }

    func testPlainKeysFollowTheLayout() {
        XCTAssertEqual(KeyCharacters.typedCharacter(for: "Q"), "Q", "letters as on keycaps")
        XCTAssertEqual(KeyCharacters.typedCharacter(for: "SEMI"), "Ö")
        XCTAssertEqual(KeyCharacters.typedCharacter(for: "MINUS"), "ß", "not SS")
        XCTAssertEqual(KeyCharacters.typedCharacter(for: "EXCL"), "!", "EXCL implies shift")
    }

    func testShortcutsAndSpecialKeysTypeNothing() {
        XCTAssertNil(KeyCharacters.typedCharacter(for: "LG(Q)"))
        XCTAssertNil(KeyCharacters.typedCharacter(for: "LC(LA(Q))"))
        XCTAssertNil(KeyCharacters.typedCharacter(for: "LSHFT"))
        XCTAssertNil(KeyCharacters.typedCharacter(for: "LEFT"))
        XCTAssertNil(KeyCharacters.typedCharacter(for: "W"), "not in this layout's table")
    }

    func testParserLabelsUseTheLayout() {
        let bindings = KeymapParser.parseBindings(from: "&kp LS(LA(N2)) &kp LG(Q) &mt LSHFT SEMI")

        XCTAssertEqual(bindings[0].displayText, "€")
        XCTAssertEqual(bindings[1].displayText, "⌘+Q")
        XCTAssertTrue(bindings[2].displayText.hasSuffix("Ö"))
    }

    func testWithoutLayoutLabelsStayAsBefore() {
        KeyCharacters.table = [:]

        XCTAssertEqual(KeymapParser.parseBindings(from: "&kp LS(LA(N2))")[0].displayText, "⇧+⌥+2")
    }
}
