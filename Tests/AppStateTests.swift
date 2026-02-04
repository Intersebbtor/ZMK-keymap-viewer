import XCTest
import Combine
import AppKit
import SwiftUI
@testable import ZMKKeymapViewerApp

final class AppStateTests: XCTestCase {
    private var appState: TestAppState!
    private var cancellables = Set<AnyCancellable>()

    override func setUpWithError() throws {
        try super.setUpWithError()
        clearAppStateDefaults()
        appState = TestAppState()
    }

    override func tearDownWithError() throws {
        cancellables.removeAll()
        appState = nil
        clearAppStateDefaults()
        try super.tearDownWithError()
    }

    func testRecentKeymapHistoryLimitsToFive() {
        (1...6).forEach { index in
            appState.addRecentKeymap("/path/\(index)")
        }

        XCTAssertEqual(appState.recentKeymaps.count, 5)
        XCTAssertEqual(appState.recentKeymaps.first, "/path/6")
        XCTAssertFalse(appState.recentKeymaps.contains("/path/1"))

        let stored = UserDefaults.standard.array(forKey: "recentKeymaps") as? [String]
        XCTAssertEqual(stored, appState.recentKeymaps)
    }

    func testAddRecentKeymapMovesExistingToFront() {
        appState.addRecentKeymap("/foo")
        appState.addRecentKeymap("/bar")
        appState.addRecentKeymap("/foo")

        XCTAssertEqual(appState.recentKeymaps, ["/foo", "/bar"])
    }

    func testClearRecentKeymaps() {
        appState.addRecentKeymap("/one")
        appState.addRecentKeymap("/two")

        appState.clearRecentKeymaps()

        XCTAssertTrue(appState.recentKeymaps.isEmpty)
        XCTAssertNil(UserDefaults.standard.array(forKey: "recentKeymaps"))
    }

    func testResetInactivityMarksHUDInactiveAfterTimeout() {
        appState.hudTimeout = 0.1

        let expectation = expectation(description: "HUD becomes inactive after timeout")
        appState.$isHUDInactive
            .sink { inactive in
                if inactive {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        appState.resetInactivity()
        XCTAssertFalse(appState.isHUDInactive)

        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(appState.isHUDInactive)
    }

    func testToggleHUDShowsPanelWhenHidden() {
        let panel = StubFloatingPanel()
        panel.fakeVisible = false
        appState.floatingPanel = panel
        appState.isHUDModeEnabled = false

        appState.toggleHUD()

        XCTAssertTrue(panel.makeKeyAndOrderFrontCalled)
        XCTAssertTrue(appState.isHUDModeEnabled)
    }

    func testToggleHUDHidesPanelWhenVisible() {
        let panel = StubFloatingPanel()
        panel.fakeVisible = true
        appState.floatingPanel = panel
        appState.isHUDModeEnabled = true

        appState.toggleHUD()

        XCTAssertTrue(panel.orderOutCalled)
        XCTAssertFalse(appState.isHUDModeEnabled)
    }

    func testHudControlSettingsPersistToUserDefaults() {
        appState.hudOpacity = 0.61
        appState.hudTimeout = 4.25
        appState.hudUseMaterial = false

        XCTAssertEqual(UserDefaults.standard.double(forKey: "hudOpacity"), 0.61, accuracy: 0.001)
        XCTAssertEqual(UserDefaults.standard.double(forKey: "hudTimeout"), 4.25, accuracy: 0.001)
        XCTAssertEqual(UserDefaults.standard.bool(forKey: "hudUseMaterial"), false)
    }

    private func clearAppStateDefaults() {
        [
            "recentKeymaps",
            "isHUDModeEnabled",
            "hudOpacity",
            "hudUseMaterial",
            "hudTimeout"
        ].forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }
}

fileprivate final class TestAppState: AppState {
    override func setupActivityMonitor() {}
}

private final class StubFloatingPanel: FloatingPanel {
    var fakeVisible = false
    var makeKeyAndOrderFrontCalled = false
    var orderOutCalled = false

    init() {
        super.init(view: AnyView(EmptyView()), contentRect: NSRect(x: 0, y: 0, width: 1, height: 1))
    }

    override var isVisible: Bool {
        fakeVisible
    }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        makeKeyAndOrderFrontCalled = true
        fakeVisible = true
    }

    override func orderOut(_ sender: Any?) {
        orderOutCalled = true
        fakeVisible = false
    }
}
