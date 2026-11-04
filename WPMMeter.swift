import Foundation

/// Typing speed from key presses, like ZMK's WPM widget on the nice!view: a
/// word is five key presses. ZMK averages over up to five seconds and then
/// starts over; this slides the five seconds along, so the number doesn't
/// jump back every five seconds.
struct WPMMeter {
    static let window: TimeInterval = 5
    static let charsPerWord = 5.0
    /// One sample a second for the graph
    static let historyLength = 30

    private var presses: [TimeInterval] = []
    private var burstStart: TimeInterval?
    private(set) var history: [Int] = []

    mutating func recordPress(at time: TimeInterval) {
        if let last = presses.last, time - last > Self.window {
            burstStart = nil
        }
        if burstStart == nil {
            burstStart = time
        }
        presses.append(time)
    }

    /// Words per minute at `time`. At the start of a burst it averages over
    /// the time typed so far (at least a second), like ZMK.
    mutating func wpm(at time: TimeInterval) -> Int {
        presses.removeAll { time - $0 > Self.window }
        guard !presses.isEmpty, let start = burstStart else {
            burstStart = nil
            return 0
        }
        let elapsed = min(Self.window, max(1, time - start))
        let count = presses.filter { time - $0 <= elapsed }.count
        return Int((Double(count) / Self.charsPerWord * 60 / elapsed).rounded())
    }

    /// Once a second: the speed now, kept for the graph
    mutating func sample(at time: TimeInterval) -> Int {
        let value = wpm(at: time)
        history.append(value)
        if history.count > Self.historyLength {
            history.removeFirst(history.count - Self.historyLength)
        }
        return value
    }

    /// Nothing typed lately and the graph is flat: no need to sample
    var isIdle: Bool {
        presses.isEmpty && history.allSatisfy { $0 == 0 }
    }

    /// Bindings that only switch layers or control the keyboard type nothing
    static func counts(_ rawCode: String) -> Bool {
        let code = rawCode.trimmingCharacters(in: .whitespaces)
        let nonTyping = ["&mo ", "&tog ", "&to ", "&sl ", "&bt ", "&out ", "&none", "&sys_reset", "&bootloader", "&studio_unlock"]
        return !nonTyping.contains { code == $0.trimmingCharacters(in: .whitespaces) || code.hasPrefix($0) }
    }
}
