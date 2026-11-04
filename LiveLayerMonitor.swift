import Foundation
import IOKit.hid

/// Listens for live layer packets from a keyboard running the
/// zmk-keypeek-layer-notifier firmware module, over USB or Bluetooth, and
/// sends reports back for the ZMK Studio RPC tunnel.
///
/// The Raw HID interface uses a vendor usage page, so opening it does not
/// need the Input Monitoring permission.
class LiveLayerMonitor: ObservableObject {
    static let usagePage = 0xFF60
    static let usage = 0x61
    private static let reportSize = 64

    /// Product name of the connected keyboard, nil while none is connected.
    @Published private(set) var connectedDeviceName: String?

    /// Called on the main thread for every decoded packet.
    var onPacket: ((LayerPacket) -> Void)?
    /// Called on the main thread when a keyboard connects or disconnects.
    var onConnectionChange: ((_ connected: Bool) -> Void)?

    private var manager: IOHIDManager?
    /// Input report buffers must stay alive as long as the device is open.
    private var reportBuffers: [IOHIDDevice: UnsafeMutablePointer<UInt8>] = [:]
    /// The device reports are sent to: the one connected last
    private var activeDevice: IOHIDDevice?

    var isRunning: Bool { manager != nil }

    func start() {
        guard manager == nil else { return }

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDPrimaryUsagePageKey: Self.usagePage,
            kIOHIDPrimaryUsageKey: Self.usage,
        ] as CFDictionary)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, Self.deviceMatched, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, Self.deviceRemoved, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            print("[LiveLayer] IOHIDManagerOpen failed: \(result)")
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            return
        }
        self.manager = manager
        print("[LiveLayer] Monitoring started")
    }

    func stop() {
        guard let manager = manager else { return }
        for device in reportBuffers.keys {
            removeDevice(device)
        }
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
        print("[LiveLayer] Monitoring stopped")
    }

    deinit {
        stop()
    }

    // MARK: - Devices

    private func addDevice(_ device: IOHIDDevice) {
        guard reportBuffers[device] == nil else { return }

        let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Keyboard"
        let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String ?? "?"

        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Self.reportSize)
        reportBuffers[device] = buffer
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, buffer, Self.reportSize, Self.reportReceived, context)

        print("[LiveLayer] Connected: \(name) via \(transport)")
        activeDevice = device
        connectedDeviceName = name
        onConnectionChange?(true)
    }

    private func removeDevice(_ device: IOHIDDevice) {
        guard let buffer = reportBuffers.removeValue(forKey: device) else { return }
        IOHIDDeviceRegisterInputReportCallback(device, buffer, Self.reportSize, nil, nil)
        buffer.deallocate()

        print("[LiveLayer] Disconnected")
        if activeDevice == device {
            activeDevice = reportBuffers.keys.first
        }
        if reportBuffers.isEmpty {
            connectedDeviceName = nil
            onConnectionChange?(false)
        }
    }

    /// Sends one output report to the keyboard. Returns false without a
    /// connected keyboard or when the report could not be sent.
    @discardableResult
    func send(_ report: [UInt8]) -> Bool {
        guard let device = activeDevice else { return false }
        let result = report.withUnsafeBufferPointer { buffer in
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, buffer.baseAddress!, buffer.count)
        }
        if result != kIOReturnSuccess {
            print("[LiveLayer] Sending report failed: \(String(format: "0x%08x", result))")
        }
        return result == kIOReturnSuccess
    }

    // MARK: - IOKit callbacks

    // The manager is scheduled on the main run loop, so all callbacks run on
    // the main thread.

    private static let deviceMatched: IOHIDDeviceCallback = { context, _, _, device in
        guard let context = context else { return }
        Unmanaged<LiveLayerMonitor>.fromOpaque(context).takeUnretainedValue().addDevice(device)
    }

    private static let deviceRemoved: IOHIDDeviceCallback = { context, _, _, device in
        guard let context = context else { return }
        Unmanaged<LiveLayerMonitor>.fromOpaque(context).takeUnretainedValue().removeDevice(device)
    }

    private static let reportReceived: IOHIDReportCallback = { context, _, _, _, _, report, length in
        guard let context = context else { return }
        let bytes = Array(UnsafeBufferPointer(start: report, count: length))
        guard let packet = LayerPacket.decode(bytes) else { return }
        Unmanaged<LiveLayerMonitor>.fromOpaque(context).takeUnretainedValue().onPacket?(packet)
    }
}
