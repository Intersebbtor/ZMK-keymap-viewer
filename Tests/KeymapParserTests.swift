import XCTest
@testable import ZMKKeymapViewerApp

/// Tests for KeymapParser focusing on parsing ZMK keymap files
class KeymapParserTests: XCTestCase {
    
    // MARK: - Test Parsing Basic Keymap
    
    func testParseSimpleKeymap() {
        let keymapData = """
        / {
            keymap {
                compatible = "zmk,keymap";
                
                default_layer {
                    label = "QWERTY";
                    bindings = <
                        &kp Q &kp W &kp E
                        &kp A &kp S &kp D
                    >;
                };
            };
        };
        """
        
        let result = KeymapParser.parse(from: keymapData)
        
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.layers.count, 1)
        XCTAssertEqual(result?.layers[0].name, "QWERTY")
        XCTAssertEqual(result?.layers[0].bindings.count, 6)
    }
    
    func testParseMultipleLayers() {
        let keymapData = """
        / {
            keymap {
                compatible = "zmk,keymap";
                
                default_layer {
                    label = "QWERTY";
                    bindings = <
                        &kp Q &kp W &kp E
                    >;
                };
                
                symbol_layer {
                    label = "SYMBOLS";
                    bindings = <
                        &kp EXCL &kp AT &kp HASH
                    >;
                };
            };
        };
        """
        
        let result = KeymapParser.parse(from: keymapData)
        
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.layers.count, 2)
        XCTAssertEqual(result?.layers[0].name, "QWERTY")
        XCTAssertEqual(result?.layers[1].name, "SYMBOLS")
    }
    
    // MARK: - Test Binding Parsing
    
    func testParseKeyBindings() {
        let keymapData = """
        / {
            keymap {
                compatible = "zmk,keymap";
                
                default_layer {
                    bindings = <
                        &kp Q &kp W &kp E
                        &kp A &kp S &kp D
                    >;
                };
            };
        };
        """
        
        let result = KeymapParser.parse(from: keymapData)
        let bindings = result?.layers[0].bindings ?? []
        
        XCTAssertEqual(bindings.count, 6)
        XCTAssertEqual(bindings[0].displayText, "Q")
        XCTAssertEqual(bindings[1].displayText, "W")
        XCTAssertEqual(bindings[2].displayText, "E")
    }
    
    func testParseModTapBindings() {
        let keymapData = """
        / {
            keymap {
                compatible = "zmk,keymap";
                
                default_layer {
                    bindings = <
                        &mt LEFT_SHIFT A &mt LEFT_CONTROL S
                    >;
                };
            };
        };
        """
        
        let result = KeymapParser.parse(from: keymapData)
        let bindings = result?.layers[0].bindings ?? []
        
        XCTAssertEqual(bindings.count, 2)
        XCTAssertTrue(bindings[0].displayText.contains("⇧"))
        XCTAssertTrue(bindings[0].displayText.contains("A"))
        XCTAssertTrue(bindings[1].displayText.contains("⌃"))
        XCTAssertTrue(bindings[1].displayText.contains("S"))
    }
    
    func testParseLayerTapBindings() {
        let keymapData = """
        / {
            keymap {
                compatible = "zmk,keymap";
                
                default_layer {
                    bindings = <
                        &lt 1 SPACE
                    >;
                };
            };
        };
        """
        
        let result = KeymapParser.parse(from: keymapData)
        let bindings = result?.layers[0].bindings ?? []
        
        XCTAssertEqual(bindings.count, 1)
        XCTAssertTrue(bindings[0].displayText.contains("L1"))
        XCTAssertTrue(bindings[0].displayText.contains("␣"))
    }
    
    func testParseMomentaryLayerBindings() {
        let keymapData = """
        / {
            keymap {
                compatible = "zmk,keymap";
                
                default_layer {
                    bindings = <
                        &mo 1 &mo 2
                    >;
                };
            };
        };
        """
        
        let result = KeymapParser.parse(from: keymapData)
        let bindings = result?.layers[0].bindings ?? []
        
        XCTAssertEqual(bindings.count, 2)
        XCTAssertEqual(bindings[0].displayText, "MO1")
        XCTAssertEqual(bindings[1].displayText, "MO2")
    }
    
    func testParseToggleLayerBindings() {
        let keymapData = """
        / {
            keymap {
                compatible = "zmk,keymap";
                
                default_layer {
                    bindings = <
                        &tog 1
                    >;
                };
            };
        };
        """
        
        let result = KeymapParser.parse(from: keymapData)
        let bindings = result?.layers[0].bindings ?? []
        
        XCTAssertEqual(bindings.count, 1)
        XCTAssertEqual(bindings[0].displayText, "TG1")
    }
    
    func testParseTransparentAndNoneBindings() {
        let keymapData = """
        / {
            keymap {
                compatible = "zmk,keymap";
                
                default_layer {
                    bindings = <
                        &trans &none
                    >;
                };
            };
        };
        """
        
        let result = KeymapParser.parse(from: keymapData)
        let bindings = result?.layers[0].bindings ?? []
        
        XCTAssertEqual(bindings.count, 2)
        XCTAssertEqual(bindings[0].displayText, "▽")
        XCTAssertEqual(bindings[1].displayText, "✕")
    }
    
    // MARK: - Test Special Keys Formatting
    
    func testFormatSpecialKeys() {
        let keymapData = """
        / {
            keymap {
                compatible = "zmk,keymap";
                
                default_layer {
                    bindings = <
                        &kp SPACE &kp TAB &kp BACKSPACE &kp RETURN
                        &kp LEFT &kp RIGHT &kp UP &kp DOWN
                    >;
                };
            };
        };
        """
        
        let result = KeymapParser.parse(from: keymapData)
        let bindings = result?.layers[0].bindings ?? []
        
        XCTAssertEqual(bindings[0].displayText, "␣")
        XCTAssertEqual(bindings[1].displayText, "⇥")
        XCTAssertEqual(bindings[2].displayText, "⌫")
        XCTAssertEqual(bindings[3].displayText, "⏎")
        XCTAssertEqual(bindings[4].displayText, "←")
        XCTAssertEqual(bindings[5].displayText, "→")
        XCTAssertEqual(bindings[6].displayText, "↑")
        XCTAssertEqual(bindings[7].displayText, "↓")
    }
    
    func testFormatModifiers() {
        let keymapData = """
        / {
            keymap {
                compatible = "zmk,keymap";
                
                default_layer {
                    bindings = <
                        &mt LEFT_SHIFT A &mt LEFT_CONTROL B &mt LEFT_ALT C &mt LEFT_GUI D
                    >;
                };
            };
        };
        """
        
        let result = KeymapParser.parse(from: keymapData)
        let bindings = result?.layers[0].bindings ?? []
        
        XCTAssertTrue(bindings[0].displayText.contains("⇧"))
        XCTAssertTrue(bindings[1].displayText.contains("⌃"))
        XCTAssertTrue(bindings[2].displayText.contains("⌥"))
        XCTAssertTrue(bindings[3].displayText.contains("⌘"))
    }
    
    // MARK: - Test Layout Detection
    
    func testDetectSweepLayout() {
        let keymapData = """
        / {
            keymap {
                compatible = "zmk,keymap";
                
                default_layer {
                    bindings = <
                        &kp Q &kp W &kp E &kp R &kp T &kp Y &kp U &kp I &kp O &kp P
                        &kp A &kp S &kp D &kp F &kp G &kp H &kp J &kp K &kp L &kp SEMICOLON
                        &kp Z &kp X &kp C &kp V &kp B &kp N &kp M &kp COMMA &kp DOT &kp SLASH
                        &mo 1 &kp SPACE &kp SPACE &mo 1
                    >;
                };
            };
        };
        """
        
        let result = KeymapParser.parse(from: keymapData)
        
        XCTAssertEqual(result?.layout.totalKeys, 34)
        XCTAssertEqual(result?.layout.name, "Sweep/Cradio")
    }
    
    func testDetectCorneLayout() {
        let keymapData = """
        / {
            keymap {
                compatible = "zmk,keymap";
                
                default_layer {
                    bindings = <
                        &kp Q &kp W &kp E &kp R &kp T &kp Y &kp U &kp I &kp O &kp P &kp LBKT &kp RBKT
                        &kp A &kp S &kp D &kp F &kp G &kp H &kp J &kp K &kp L &kp SEMICOLON &kp APOSTROPHE &kp ENTER
                        &kp Z &kp X &kp C &kp V &kp B &kp N &kp M &kp COMMA &kp DOT &kp SLASH &kp SLASH &kp RSHIFT
                        &kp LCTRL &kp LALT &kp LGUI &kp SPACE &kp BSPC &kp DEL
                    >;
                };
            };
        };
        """
        
        let result = KeymapParser.parse(from: keymapData)
        
        XCTAssertEqual(result?.layout.totalKeys, 42)
        XCTAssertEqual(result?.layout.name, "Corne")
    }
    
    // MARK: - Test Row and Column Detection
    
    func testCalculateRowsAndColumns() {
        let keymapData = """
        / {
            keymap {
                compatible = "zmk,keymap";
                
                default_layer {
                    bindings = <
                        &kp Q &kp W &kp E
                        &kp A &kp S &kp D
                    >;
                };
            };
        };
        """
        
        let result = KeymapParser.parse(from: keymapData)
        let layer = result?.layers[0]
        
        XCTAssertEqual(layer?.rowCount, 2)
        XCTAssertEqual(layer?.columnCount, 3)
    }
    
    func testUniformRowsAndColumns() {
        let keymapData = """
        / {
            keymap {
                compatible = "zmk,keymap";
                
                default_layer {
                    bindings = <
                        &kp Q &kp W &kp E &kp R
                        &kp A &kp S &kp D &kp F
                        &kp Z &kp X &kp C &kp V
                    >;
                };
            };
        };
        """
        
        let result = KeymapParser.parse(from: keymapData)
        let layer = result?.layers[0]
        
        XCTAssertEqual(layer?.rowCount, 3)
        XCTAssertEqual(layer?.columnCount, 4)
    }
    
    // MARK: - Test Edge Cases
    
    func testParseEmptyKeymap() {
        let keymapData = """
        / {
            keymap {
                compatible = "zmk,keymap";
            };
        };
        """
        
        let result = KeymapParser.parse(from: keymapData)
        XCTAssertNil(result) // Should fail if no layers found
    }
    
    func testParseMissingKeymapSection() {
        let keymapData = """
        / {
            behaviors {
                compatible = "zmk,behaviors";
            };
        };
        """
        
        let result = KeymapParser.parse(from: keymapData)
        XCTAssertNil(result)
    }
    
    func testParseWithWhitespaceAndComments() {
        let keymapData = """
        / {
            keymap {
                compatible = "zmk,keymap";
                
                // This is a comment
                default_layer {
                    label = "Default";
                    /* Multi-line
                       comment */
                    bindings = <
                        &kp Q &kp W
                    >;
                };
            };
        };
        """
        
        let result = KeymapParser.parse(from: keymapData)
        
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.layers[0].bindings.count, 2)
    }
    
    func testParseWithInlineComments() {
        let keymapData = """
        / {
            keymap {
                compatible = "zmk,keymap";
                
                default_layer {
                    label = "QWERTY"; /* layer label */
                    bindings = <
                        &kp Q /* Q key */ &kp W /* W key */
                        &kp A &kp S /* home row */
                    >;
                };
            };
        };
        """
        
        let result = KeymapParser.parse(from: keymapData)
        
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.layers[0].bindings.count, 4)
        XCTAssertEqual(result?.layers[0].bindings[0].displayText, "Q")
        XCTAssertEqual(result?.layers[0].bindings[1].displayText, "W")
    }
    
    func testParseWithCppStyleComments() {
        let keymapData = """
        / {
            keymap {
                compatible = "zmk,keymap";
                
                default_layer {
                    label = "Default"; // This is the default layer
                    bindings = < // bindings start
                        &kp Q &kp W // Q and W keys
                        &kp A &kp S // A and S keys
                    >;
                };
            };
        };
        """
        
        let result = KeymapParser.parse(from: keymapData)
        
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.layers[0].bindings.count, 4)
    }
    
    func testParseNestedComments() {
        let keymapData = """
        / {
            keymap {
                compatible = "zmk,keymap";
                
                default_layer {
                    label = "Default";
                    /* This is a /* nested */ comment test */
                    bindings = <
                        &kp Q &kp W
                    >;
                };
            };
        };
        """
        
        let result = KeymapParser.parse(from: keymapData)
        
        XCTAssertNotNil(result)
        // Should still parse correctly despite nested comment syntax
        XCTAssertGreaterThan(result?.layers[0].bindings.count ?? 0, 0)
    }
    
    func testParseCommentsBetweenBindings() {
        let keymapData = """
        / {
            keymap {
                compatible = "zmk,keymap";
                
                default_layer {
                    label = "Default";
                    bindings = <
                        /* Row 1 */ &kp Q &kp W &kp E
                        /* Row 2 */ &kp A &kp S &kp D
                    >;
                };
            };
        };
        """
        
        let result = KeymapParser.parse(from: keymapData)
        
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.layers[0].bindings.count, 6)
    }
    
    func testParseCustomModTapBindings() {
        let keymapData = """
        / {
            keymap {
                compatible = "zmk,keymap";
                
                default_layer {
                    bindings = <
                        &long_MT LEFT_CONTROL A
                    >;
                };
            };
        };
        """
        
        let result = KeymapParser.parse(from: keymapData)
        let bindings = result?.layers[0].bindings ?? []
        
        XCTAssertEqual(bindings.count, 1)
        XCTAssertTrue(bindings[0].displayText.contains("⌃"))
    }
    
    func testParseBluetoothBindings() {
        let keymapData = """
        / {
            keymap {
                compatible = "zmk,keymap";
                
                default_layer {
                    bindings = <
                        &bt BT_SEL 0 &bt BT_CLR
                    >;
                };
            };
        };
        """
        
        let result = KeymapParser.parse(from: keymapData)
        let bindings = result?.layers[0].bindings ?? []
        
        XCTAssertEqual(bindings.count, 2)
        XCTAssertEqual(bindings[0].displayText, "BT0")
        XCTAssertEqual(bindings[1].displayText, "BT CLR")
    }
    
    func testParseSystemBindings() {
        let keymapData = """
        / {
            keymap {
                compatible = "zmk,keymap";
                
                default_layer {
                    bindings = <
                        &sys_reset &bootloader
                    >;
                };
            };
        };
        """
        
        let result = KeymapParser.parse(from: keymapData)
        let bindings = result?.layers[0].bindings ?? []
        
        XCTAssertEqual(bindings.count, 2)
        XCTAssertEqual(bindings[0].displayText, "RESET")
        XCTAssertEqual(bindings[1].displayText, "BOOT")
    }
    
    // MARK: - Test Behavior Parsing
    
    func testParseBehaviors() {
        let keymapData = """
        / {
            behaviors {
                long_MT: behavior_mod_tap {
                    label = "LONG_MOD_TAP";
                };
                short_LT: behavior_layer_tap {
                    label = "SHORT_LAYER_TAP";
                };
            };
            
            keymap {
                compatible = "zmk,keymap";
                
                default_layer {
                    bindings = <
                        &kp Q
                    >;
                };
            };
        };
        """
        
        let result = KeymapParser.parse(from: keymapData)
        
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.behaviors.count, 2)
        XCTAssertEqual(result?.behaviors["long_MT"], "LONG_MOD_TAP")
        XCTAssertEqual(result?.behaviors["short_LT"], "SHORT_LAYER_TAP")
    }
}
