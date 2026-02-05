import XCTest
@testable import ZMKKeymapViewerApp

final class KeymapParserAliasTest: XCTestCase {
    
    // MARK: - Basic Alias Parsing
    
    func testAliasExtractedFromSingleBinding() {
        let input = "&kp LS(LA(LG(K)))  // =Magnet Right"
        let bindings = KeymapParser.parseBindings(from: input)
        
        XCTAssertEqual(bindings.count, 1)
        XCTAssertEqual(bindings[0].alias, "Magnet Right")
        XCTAssertEqual(bindings[0].effectiveDisplayText, "Magnet Right")
        // Raw code should NOT contain the comment
        XCTAssertFalse(bindings[0].rawCode.contains("//"))
    }
    
    func testAliasWithNoSpace() {
        let input = "&kp A  // =Letter A"
        let bindings = KeymapParser.parseBindings(from: input)
        
        XCTAssertEqual(bindings.count, 1)
        XCTAssertEqual(bindings[0].alias, "Letter A")
    }
    
    func testAliasWithSpaceAfterEquals() {
        let input = "&kp A  // = Spaced Alias"
        let bindings = KeymapParser.parseBindings(from: input)
        
        XCTAssertEqual(bindings.count, 1)
        XCTAssertEqual(bindings[0].alias, "Spaced Alias")
    }
    
    // MARK: - Regular Comments (No Alias)
    
    func testRegularCommentNotTreatedAsAlias() {
        let input = "&kp A  // This is just a comment"
        let bindings = KeymapParser.parseBindings(from: input)
        
        XCTAssertEqual(bindings.count, 1)
        XCTAssertNil(bindings[0].alias)
        XCTAssertEqual(bindings[0].displayText, "A")
        XCTAssertEqual(bindings[0].effectiveDisplayText, "A")
    }
    
    func testNoCommentMeansNoAlias() {
        let input = "&kp B"
        let bindings = KeymapParser.parseBindings(from: input)
        
        XCTAssertEqual(bindings.count, 1)
        XCTAssertNil(bindings[0].alias)
    }
    
    // MARK: - Multiple Bindings Per Line
    
    func testAliasAppliesOnlyToLastBindingOnLine() {
        // Multiple bindings on one line - alias should apply to the LAST one
        let input = "&kp A  &kp B  &kp C  // =Charlie"
        let bindings = KeymapParser.parseBindings(from: input)
        
        XCTAssertEqual(bindings.count, 3)
        XCTAssertNil(bindings[0].alias) // A - no alias
        XCTAssertNil(bindings[1].alias) // B - no alias
        XCTAssertEqual(bindings[2].alias, "Charlie") // C - has alias
    }
    
    // MARK: - Multi-Line Bindings
    
    func testMultipleLinesWithDifferentAliases() {
        let input = """
        &kp A  // =Alpha
        &kp B  // =Bravo
        &kp C
        """
        let bindings = KeymapParser.parseBindings(from: input)
        
        XCTAssertEqual(bindings.count, 3)
        XCTAssertEqual(bindings[0].alias, "Alpha")
        XCTAssertEqual(bindings[1].alias, "Bravo")
        XCTAssertNil(bindings[2].alias)
    }
    
    // MARK: - Edge Cases
    
    func testEmptyAliasIgnored() {
        let input = "&kp A  // ="
        let bindings = KeymapParser.parseBindings(from: input)
        
        XCTAssertEqual(bindings.count, 1)
        XCTAssertNil(bindings[0].alias)
    }
    
    func testAliasWithSpecialCharacters() {
        let input = "&kp A  // =ä (umlaut)"
        let bindings = KeymapParser.parseBindings(from: input)
        
        XCTAssertEqual(bindings.count, 1)
        XCTAssertEqual(bindings[0].alias, "ä (umlaut)")
    }
    
    func testAliasWithEmoji() {
        let input = "&kp A  // =🔥 Fire Key"
        let bindings = KeymapParser.parseBindings(from: input)
        
        XCTAssertEqual(bindings.count, 1)
        XCTAssertEqual(bindings[0].alias, "🔥 Fire Key")
    }
    
    // MARK: - Real-World Examples
    
    func testMagnetShortcuts() {
        let input = """
        &kp LC(LA(LEFT))    // =Magnet Left
        &kp LC(LA(E))       // =Arc Tab 1
        &kp LC(LA(R))       // =Arc Tab 2
        &kp LC(LA(T))       // =Arc Tab 3
        &kp LC(LA(RIGHT))   // =Magnet Right
        """
        let bindings = KeymapParser.parseBindings(from: input)
        
        XCTAssertEqual(bindings.count, 5)
        XCTAssertEqual(bindings[0].alias, "Magnet Left")
        XCTAssertEqual(bindings[1].alias, "Arc Tab 1")
        XCTAssertEqual(bindings[2].alias, "Arc Tab 2")
        XCTAssertEqual(bindings[3].alias, "Arc Tab 3")
        XCTAssertEqual(bindings[4].alias, "Magnet Right")
        
        // effectiveDisplayText should return alias
        XCTAssertEqual(bindings[0].effectiveDisplayText, "Magnet Left")
    }
    
    func testMixedAliasAndRegularComments() {
        let input = """
        &kp A  // =Alpha
        &kp B  // just a note
        &kp C  // =Charlie
        """
        let bindings = KeymapParser.parseBindings(from: input)
        
        XCTAssertEqual(bindings[0].alias, "Alpha")
        XCTAssertNil(bindings[1].alias)
        XCTAssertEqual(bindings[2].alias, "Charlie")
    }
}
