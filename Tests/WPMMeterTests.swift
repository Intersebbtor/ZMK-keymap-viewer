import XCTest
@testable import ZMKKeymapViewerApp

/// Typing speed as ZMK's nice!view widget counts it: five key presses a word
class WPMMeterTests: XCTestCase {

    /// `perSecond` presses a second from `start` for `seconds`
    private func type(_ meter: inout WPMMeter, perSecond: Double, seconds: Double, from start: Double = 0) {
        var time = start
        while time < start + seconds {
            meter.recordPress(at: time)
            time += 1 / perSecond
        }
    }

    func testSteadyTyping() {
        var meter = WPMMeter()
        type(&meter, perSecond: 6, seconds: 10)

        // 6 key presses a second are 72 words a minute; a press right on the
        // window's edge may or may not count
        XCTAssertEqual(Double(meter.wpm(at: 10)), 72, accuracy: 3)
    }

    func testStartOfABurstUsesTheTimeTypedSoFar() {
        var meter = WPMMeter()
        type(&meter, perSecond: 6, seconds: 2)

        XCTAssertEqual(Double(meter.wpm(at: 2)), 72, accuracy: 3)
    }

    func testDropsToZeroAfterThePause() {
        var meter = WPMMeter()
        type(&meter, perSecond: 6, seconds: 10)

        XCTAssertGreaterThan(meter.wpm(at: 12), 0)
        XCTAssertEqual(meter.wpm(at: 16), 0)
    }

    func testANewBurstStartsFresh() {
        var meter = WPMMeter()
        type(&meter, perSecond: 6, seconds: 5)
        type(&meter, perSecond: 3, seconds: 2, from: 20)

        XCTAssertEqual(Double(meter.wpm(at: 22)), 36, accuracy: 6)
    }

    func testHistoryKeepsThirtySeconds() {
        var meter = WPMMeter()
        type(&meter, perSecond: 6, seconds: 5)
        for second in 1...40 {
            _ = meter.sample(at: Double(second))
        }

        XCTAssertEqual(meter.history.count, 30)
        XCTAssertTrue(meter.isIdle, "flat after the pause")
    }

    func testLayerAndKeyboardKeysDontCount() {
        XCTAssertTrue(WPMMeter.counts("&kp A"))
        XCTAssertTrue(WPMMeter.counts("&mt LSHFT Z"))
        XCTAssertTrue(WPMMeter.counts("&lt 1 BSPC"))
        XCTAssertTrue(WPMMeter.counts("&trans"))
        XCTAssertFalse(WPMMeter.counts("&mo 2"))
        XCTAssertFalse(WPMMeter.counts("&tog 4"))
        XCTAssertFalse(WPMMeter.counts("&bt BT_SEL 0"))
        XCTAssertFalse(WPMMeter.counts("&none"))
        XCTAssertFalse(WPMMeter.counts("&studio_unlock"))
    }
}
