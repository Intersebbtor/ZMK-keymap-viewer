import XCTest
@testable import ZMKKeymapViewerApp

final class KeymapParserAliasTest: XCTestCase {
    
    // MARK: - Inline Block Comment Aliases /* =alias */
    
    func testInlineAliasWithBlockComment() {
        let input = "&kp LS(LA(LG(K))) /* =Magnet Right */"
        let bindings = KeymapParser.parseBindings(from: input)
        
        XCTAssertEqual(bindings.count, 1)
        XCTAssertEqual(bindings[0].alias, "Magnet Right")
        XCTAssertEqual(bindings[0].effectiveDisplayText, "Magnet Right")
        XCTAssertEqual(bindings[0].rawCode, "&kp LS(LA(LG(K)))")
    }
    
    func testInlineAliasInMiddleOfLine() {
        // This is the key use case - alias in middle of line without breaking subsequent bindings
        let input = "&kp A  &kp LC(LA(LG(C))) /* =Finder */  &kp TILDE"
        let bindings = KeymapParser.parseBindings(from: input)
        
        XCTAssertEqual(bindings.count, 3)
        XCTAssertNil(bindings[0].alias) // A - no alias
        XCTAssertEqual(bindings[1].alias, "Finder") // LC(LA(LG(C))) - has alias
        XCTAssertNil(bindings[2].alias) // TILDE - no alias
        XCTAssertEqual(bindings[2].displayText, "~") // Verify TILDE wasn't lost
    }
    
    func testMultipleInlineAliasesOnSameLine() {
        let input = "&kp A /* =Alpha */  &kp B /* =Bravo */  &kp C"
        let bindings = KeymapParser.parseBindings(from: input)
        
        XCTAssertEqual(bindings.count, 3)
        XCTAssertEqual(bindings[0].alias, "Alpha")
        XCTAssertEqual(bindings[1].alias, "Bravo")
        XCTAssertNil(bindings[2].alias)
    }
    
    // MARK: - End-of-Line // =alias (no longer supported, plain comment)

    func testEndOfLineAliasSyntaxIsIgnored() {
        let input = "&kp A  // =Letter A"
        let bindings = KeymapParser.parseBindings(from: input)

        XCTAssertEqual(bindings.count, 1)
        XCTAssertNil(bindings[0].alias)
    }

    func testEndOfLineAliasSyntaxIsIgnoredForAllBindings() {
        let input = "&kp A  &kp B  &kp C  // =Charlie"
        let bindings = KeymapParser.parseBindings(from: input)

        XCTAssertEqual(bindings.count, 3)
        XCTAssertNil(bindings[0].alias)
        XCTAssertNil(bindings[1].alias)
        XCTAssertNil(bindings[2].alias)
    }
    
    // MARK: - Regular Comments (No Alias)
    
    func testRegularLineCommentNotTreatedAsAlias() {
        let input = "&kp A  // This is just a comment"
        let bindings = KeymapParser.parseBindings(from: input)
        
        XCTAssertEqual(bindings.count, 1)
        XCTAssertNil(bindings[0].alias)
    }
    
    func testRegularBlockCommentNotTreatedAsAlias() {
        let input = "&kp A /* just a comment */"
        let bindings = KeymapParser.parseBindings(from: input)
        
        XCTAssertEqual(bindings.count, 1)
        XCTAssertNil(bindings[0].alias)
    }
    
    func testNoCommentMeansNoAlias() {
        let input = "&kp B"
        let bindings = KeymapParser.parseBindings(from: input)
        
        XCTAssertEqual(bindings.count, 1)
        XCTAssertNil(bindings[0].alias)
    }
    
    // MARK: - Multi-Line Bindings
    
    func testMultipleLinesWithDifferentAliases() {
        let input = """
        &kp A /* =Alpha */
        &kp B  // =Bravo
        &kp C
        """
        let bindings = KeymapParser.parseBindings(from: input)
        
        XCTAssertEqual(bindings.count, 3)
        XCTAssertEqual(bindings[0].alias, "Alpha")
        XCTAssertNil(bindings[1].alias)
        XCTAssertNil(bindings[2].alias)
    }

    // MARK: - Edge Cases
    
    func testEmptyAliasIgnored() {
        let input = "&kp A /* = */"
        let bindings = KeymapParser.parseBindings(from: input)
        
        XCTAssertEqual(bindings.count, 1)
        XCTAssertNil(bindings[0].alias)
    }
    
    func testAliasWithSpecialCharacters() {
        let input = "&kp A /* =ä (umlaut) */"
        let bindings = KeymapParser.parseBindings(from: input)
        
        XCTAssertEqual(bindings.count, 1)
        XCTAssertEqual(bindings[0].alias, "ä (umlaut)")
    }
    
    func testAliasWithEmoji() {
        let input = "&kp A /* =🔥 Fire Key */"
        let bindings = KeymapParser.parseBindings(from: input)
        
        XCTAssertEqual(bindings.count, 1)
        XCTAssertEqual(bindings[0].alias, "🔥 Fire Key")
    }
    
    // MARK: - Real-World Examples
    
    func testMagnetShortcutsInline() {
        let input = """
        &kp LC(LA(LEFT)) /* =⬅️ Left */  &kp LC(LA(E)) /* =Arc 1 */  &kp LC(LA(R)) /* =Arc 2 */  &kp LC(LA(T)) /* =Arc 3 */  &kp LC(LA(RIGHT)) /* =➡️ Right */
        """
        let bindings = KeymapParser.parseBindings(from: input)
        
        XCTAssertEqual(bindings.count, 5)
        XCTAssertEqual(bindings[0].alias, "⬅️ Left")
        XCTAssertEqual(bindings[1].alias, "Arc 1")
        XCTAssertEqual(bindings[2].alias, "Arc 2")
        XCTAssertEqual(bindings[3].alias, "Arc 3")
        XCTAssertEqual(bindings[4].alias, "➡️ Right")
    }
}
