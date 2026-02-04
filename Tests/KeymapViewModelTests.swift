import XCTest
@testable import ZMKKeymapViewerApp

/// Tests for KeymapViewModel functionality
class KeymapViewModelTests: XCTestCase {
    
    var viewModel: KeymapViewModel!
    var testFilePath: String!
    
    override func setUp() {
        super.setUp()
        viewModel = KeymapViewModel()
        
        // Create a temporary test keymap file
        let tempDir = NSTemporaryDirectory()
        testFilePath = tempDir + "test_keymap.devicetree"
        
        let testKeymapData = """
        / {
            keymap {
                compatible = "zmk,keymap";
                
                default_layer {
                    label = "QWERTY";
                    bindings = <
                        &kp Q &kp W &kp E &kp R &kp T &kp Y &kp U &kp I &kp O &kp P
                        &kp A &kp S &kp D &kp F &kp G &kp H &kp J &kp K &kp L &kp SEMICOLON
                        &kp Z &kp X &kp C &kp V &kp B &kp N &kp M &kp COMMA &kp DOT &kp SLASH
                        &mo 1 &kp SPACE &kp SPACE &mo 1
                    >;
                };
                
                symbol_layer {
                    label = "SYMBOLS";
                    bindings = <
                        &kp EXCL &kp AT &kp HASH &kp DLLR &kp PRCNT &kp CARET &kp AMPS &kp STAR &kp LPAR &kp RPAR
                        &kp MINUS &kp EQUAL &kp LBKT &kp RBKT &kp BSLH &kp SEMI &kp APOSTROPHE &kp NONE &kp NONE &kp NONE
                        &kp TILDE &kp GRAVE &kp LT &kp GT &kp QUESTION &kp COLON &kp DOUBLE_QUOTES &kp NONE &kp NONE &kp NONE
                        &trans &kp SPACE &kp SPACE &trans
                    >;
                };
            };
        };
        """
        
        try? testKeymapData.write(toFile: testFilePath, atomically: true, encoding: .utf8)
    }
    
    override func tearDown() {
        // Clean up test file
        try? FileManager.default.removeItem(atPath: testFilePath)
        super.tearDown()
    }
    
    // MARK: - Test Initialization
    
    func testViewModelInitialization() {
        XCTAssertNil(viewModel.keymap)
        XCTAssertNil(viewModel.currentFilePath)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }
    
    // MARK: - Test Loading Keymap
    
    func testLoadKeymapFromValidFile() {
        let expectation = XCTestExpectation(description: "Keymap loaded")
        
        var keymapLoaded = false
        let cancellable = viewModel.$keymap.sink { keymap in
            if keymap != nil && !keymapLoaded {
                keymapLoaded = true
                expectation.fulfill()
            }
        }
        
        viewModel.loadKeymap(from: testFilePath)
        
        wait(for: [expectation], timeout: 2.0)
        
        XCTAssertNotNil(viewModel.keymap)
        XCTAssertEqual(viewModel.currentFilePath, testFilePath)
        XCTAssertEqual(viewModel.keymap?.layers.count, 2)
        XCTAssertEqual(viewModel.keymap?.layers[0].name, "QWERTY")
        
        cancellable.cancel()
    }
    
    func testLoadKeymapWithInvalidPath() {
        let expectation = XCTestExpectation(description: "Error received")
        
        var errorReceived = false
        let cancellable = viewModel.$errorMessage.sink { error in
            if error != nil && !errorReceived {
                errorReceived = true
                expectation.fulfill()
            }
        }
        
        viewModel.loadKeymap(from: "/invalid/path/keymap.devicetree")
        
        wait(for: [expectation], timeout: 2.0)
        
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertNil(viewModel.keymap)
        
        cancellable.cancel()
    }
    
    func testLoadKeymapWithEmptyPath() {
        viewModel.loadKeymap(from: "")
        
        // Should handle gracefully without crashing
        XCTAssertNil(viewModel.keymap)
    }
    
    func testLoadKeymapSetsCurrentFilePath() {
        let expectation = XCTestExpectation(description: "File path set")
        
        var pathSet = false
        let cancellable = viewModel.$currentFilePath.sink { path in
            if path != nil && !pathSet {
                pathSet = true
                expectation.fulfill()
            }
        }
        
        viewModel.loadKeymap(from: testFilePath)
        
        wait(for: [expectation], timeout: 2.0)
        
        XCTAssertEqual(viewModel.currentFilePath, testFilePath)
        
        cancellable.cancel()
    }
    
    // MARK: - Test IsLoading State
    
    func testIsLoadingState() {
        let expectation = XCTestExpectation(description: "Loading state updated")
        
        var loadingStates: [Bool] = []
        let cancellable = viewModel.$isLoading.sink { isLoading in
            loadingStates.append(isLoading)
            // Initial is false, then true during load, then false after load
            if loadingStates.count >= 3 && !isLoading {
                expectation.fulfill()
            }
        }
        
        viewModel.loadKeymap(from: testFilePath)
        
        wait(for: [expectation], timeout: 2.0)
        
        XCTAssertFalse(viewModel.isLoading)
        
        cancellable.cancel()
    }
    
    // MARK: - Test Error Handling
    
    func testErrorMessageCleared() {
        let expectation = XCTestExpectation(description: "Error cleared")
        
        var errorCleared = false
        let cancellable = viewModel.$errorMessage.sink { error in
            if error == nil && !errorCleared {
                errorCleared = true
                expectation.fulfill()
            }
        }
        
        viewModel.errorMessage = "Some error"
        viewModel.loadKeymap(from: testFilePath)
        
        wait(for: [expectation], timeout: 2.0)
        
        XCTAssertNil(viewModel.errorMessage)
        
        cancellable.cancel()
    }
    
    // MARK: - Test Reload Current Keymap
    
    func testReloadCurrentKeymap() {
        let expectation = XCTestExpectation(description: "Keymap reloaded")
        
        var reloadCount = 0
        let cancellable = viewModel.$keymap.sink { keymap in
            if keymap != nil {
                reloadCount += 1
                if reloadCount >= 2 {
                    expectation.fulfill()
                }
            }
        }
        
        viewModel.loadKeymap(from: testFilePath)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.viewModel.reloadCurrentKeymap()
        }
        
        wait(for: [expectation], timeout: 2.0)
        
        cancellable.cancel()
    }
    
    func testReloadWithoutCurrentPath() {
        let expectation = XCTestExpectation(description: "No reload without path")
        
        // Set a small delay to ensure no state change
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        
        viewModel.reloadCurrentKeymap()
        
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertNil(viewModel.keymap)
    }
    
    // MARK: - Test UserDefaults Integration
    
    func testSaveToUserDefaults() {
        let expectation = XCTestExpectation(description: "Saved to UserDefaults")
        
        var saved = false
        let cancellable = viewModel.$currentFilePath.sink { path in
            if path != nil && !saved {
                saved = true
                expectation.fulfill()
            }
        }
        
        viewModel.loadKeymap(from: testFilePath)
        
        wait(for: [expectation], timeout: 2.0)
        
        let savedPath = UserDefaults.standard.string(forKey: "lastKeymapPath")
        XCTAssertEqual(savedPath, testFilePath)
        
        // Clean up
        UserDefaults.standard.removeObject(forKey: "lastKeymapPath")
        
        cancellable.cancel()
    }
    
    // MARK: - Test Keymap Content
    
    func testLoadedKeymapContainsLayers() {
        let expectation = XCTestExpectation(description: "Layers loaded")
        
        var layersLoaded = false
        let cancellable = viewModel.$keymap.sink { keymap in
            if let keymap = keymap, !keymap.layers.isEmpty, !layersLoaded {
                layersLoaded = true
                expectation.fulfill()
            }
        }
        
        viewModel.loadKeymap(from: testFilePath)
        
        wait(for: [expectation], timeout: 2.0)
        
        guard let keymap = viewModel.keymap else {
            XCTFail("Keymap should be loaded")
            cancellable.cancel()
            return
        }
        
        XCTAssertGreaterThan(keymap.layers.count, 0)
        XCTAssertEqual(keymap.layers[0].name, "QWERTY")
        
        cancellable.cancel()
    }
    
    func testLoadedKeymapHasBindings() {
        let expectation = XCTestExpectation(description: "Bindings loaded")
        
        var bindingsLoaded = false
        let cancellable = viewModel.$keymap.sink { keymap in
            if let keymap = keymap, !keymap.layers.isEmpty {
                let firstLayer = keymap.layers[0]
                if !firstLayer.bindings.isEmpty && !bindingsLoaded {
                    bindingsLoaded = true
                    expectation.fulfill()
                }
            }
        }
        
        viewModel.loadKeymap(from: testFilePath)
        
        wait(for: [expectation], timeout: 2.0)
        
        guard let keymap = viewModel.keymap, let firstLayer = keymap.layers.first else {
            XCTFail("Keymap and layer should be loaded")
            cancellable.cancel()
            return
        }
        
        XCTAssertGreaterThan(firstLayer.bindings.count, 0)
        
        cancellable.cancel()
    }
    
    func testLoadedKeymapHasLayout() {
        let expectation = XCTestExpectation(description: "Layout detected")
        
        var layoutDetected = false
        let cancellable = viewModel.$keymap.sink { keymap in
            if let keymap = keymap, !layoutDetected {
                layoutDetected = true
                expectation.fulfill()
            }
        }
        
        viewModel.loadKeymap(from: testFilePath)
        
        wait(for: [expectation], timeout: 2.0)
        
        guard let keymap = viewModel.keymap else {
            XCTFail("Keymap should be loaded")
            cancellable.cancel()
            return
        }
        
        XCTAssertGreaterThan(keymap.layout.totalKeys, 0)
        
        cancellable.cancel()
    }
    
    // MARK: - Test Multiple Loads
    
    func testLoadDifferentKeymap() {
        let expectation = XCTestExpectation(description: "Different keymap loaded")
        
        let tempDir = NSTemporaryDirectory()
        let secondFilePath = tempDir + "test_keymap_2.devicetree"
        
        let secondKeymapData = """
        / {
            keymap {
                compatible = "zmk,keymap";
                
                default_layer {
                    label = "COLEMAK";
                    bindings = <
                        &kp Q &kp W
                    >;
                };
            };
        };
        """
        
        try? secondKeymapData.write(toFile: secondFilePath, atomically: true, encoding: .utf8)
        
        var loadCount = 0
        let cancellable = viewModel.$keymap.sink { keymap in
            if keymap != nil {
                loadCount += 1
                if loadCount >= 2 {
                    expectation.fulfill()
                }
            }
        }
        
        viewModel.loadKeymap(from: testFilePath)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.viewModel.loadKeymap(from: secondFilePath)
        }
        
        wait(for: [expectation], timeout: 2.0)
        
        XCTAssertEqual(viewModel.keymap?.layers[0].name, "COLEMAK")
        XCTAssertEqual(viewModel.currentFilePath, secondFilePath)
        
        // Clean up
        try? FileManager.default.removeItem(atPath: secondFilePath)
        
        cancellable.cancel()
    }
}
