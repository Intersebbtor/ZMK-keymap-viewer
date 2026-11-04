import Foundation

/// Everything the viewer needs from the keyboard to show its keymap
struct StudioSnapshot: Equatable {
    let deviceName: String
    let layers: [StudioLayer]
    /// The active physical layout, nil if the keyboard has none
    let layout: StudioPhysicalLayout?
    let behaviors: [UInt32: StudioBehavior]
}

/// Sends ZMK Studio requests one at a time and matches the responses.
/// The transport is a closure that sends one Raw HID report; responses come
/// in through `receive(_:)`.
@MainActor
final class StudioClient {
    static let timeout: TimeInterval = 3

    private let sendReport: ([UInt8]) -> Bool
    private var decoder = StudioFraming.Decoder()
    private var nextRequestID: UInt32 = 1
    private var pending: (id: UInt32, continuation: CheckedContinuation<StudioResult, Error>)?

    /// Every reassembled message, for recording test fixtures
    var onMessage: (([UInt8]) -> Void)?
    /// The keyboard was locked or unlocked (&studio_unlock)
    var onLockStateChanged: ((StudioLockState) -> Void)?

    init(sendReport: @escaping ([UInt8]) -> Bool) {
        self.sendReport = sendReport
    }

    /// Feeds the payload of a 0xF2 report
    func receive(_ payload: [UInt8]) {
        for message in decoder.feed(payload) {
            onMessage?(message)
            let response = try? StudioResponse.decode(message)
            if case let .notification(lockState?)? = response {
                onLockStateChanged?(lockState)
            }
            guard case let .requestResponse(id, result)? = response,
                  let pending = pending, pending.id == id else { continue }
            self.pending = nil
            pending.continuation.resume(returning: result)
        }
    }

    /// Fails the request in flight, e.g. when the keyboard disconnects
    func cancel(with error: StudioError = .notConnected) {
        decoder = StudioFraming.Decoder()
        guard let pending = pending else { return }
        self.pending = nil
        pending.continuation.resume(throwing: error)
    }

    func call(_ request: StudioRequest) async throws -> StudioResult {
        // One request at a time: wait for the one in flight (it ends with its
        // response or its timeout)
        while pending != nil {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let id = nextRequestID
        nextRequestID &+= 1

        let reports = StudioHIDTunnel.reports(for: StudioFraming.frame(request.encoded(requestID: id)))
        let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<StudioResult, Error>) in
            pending = (id, continuation)
            guard reports.allSatisfy(sendReport) else {
                cancel(with: .notConnected)
                return
            }
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Self.timeout * 1_000_000_000))
                guard let self = self, self.pending?.id == id else { return }
                self.cancel(with: .timeout)
            }
        }

        switch result {
        case .error(code: 1):
            throw StudioError.locked
        case let .error(code):
            throw StudioError.device(code: code)
        default:
            return result
        }
    }

    // MARK: - Reading the keymap

    func lockState() async throws -> StudioLockState {
        guard case let .lockState(state) = try await call(.getLockState) else { throw StudioError.unexpectedResponse }
        return state
    }

    func fetchSnapshot() async throws -> StudioSnapshot {
        guard case let .deviceInfo(name) = try await call(.getDeviceInfo) else { throw StudioError.unexpectedResponse }
        guard try await lockState() == .unlocked else { throw StudioError.locked }

        guard case let .keymap(layers) = try await call(.getKeymap) else { throw StudioError.unexpectedResponse }
        guard case let .physicalLayouts(active, layouts) = try await call(.getPhysicalLayouts) else {
            throw StudioError.unexpectedResponse
        }
        guard case let .behaviorIDs(ids) = try await call(.listAllBehaviors) else { throw StudioError.unexpectedResponse }

        // Only the behaviors the keymap uses
        let usedIDs = Set(layers.flatMap { $0.bindings.map { UInt32(bitPattern: $0.behaviorID) } })
        var behaviors: [UInt32: StudioBehavior] = [:]
        for id in ids where usedIDs.contains(id) {
            guard case let .behavior(behavior) = try await call(.getBehaviorDetails(id: id)) else {
                throw StudioError.unexpectedResponse
            }
            behaviors[id] = behavior
        }

        return StudioSnapshot(
            deviceName: name,
            layers: layers,
            layout: layouts.indices.contains(active) ? layouts[active] : layouts.first,
            behaviors: behaviors
        )
    }
}
