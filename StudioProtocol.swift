import Foundation

// ZMK Studio RPC over the Raw HID tunnel of zmk-keypeek-layer-notifier.
//
// Layers, from the wire up:
// 1. Raw HID reports: [0xF2, length (1...30), payload...], 32 bytes each
// 2. Framing: SOF 0xAB, data with 0xAB/0xAC/0xAD escaped by 0xAC, EOF 0xAD
// 3. Protobuf messages from zmk-studio-messages (studio.proto and friends)
//
// Only read-only requests are implemented, so the viewer can never change
// the keyboard's keymap.

// MARK: - HID tunnel

enum StudioHIDTunnel {
    static let marker: UInt8 = 0xF2
    static let reportSize = 32
    static let maxPayload = reportSize - 2

    /// Splits framed bytes into 32-byte reports
    static func reports(for framed: [UInt8]) -> [[UInt8]] {
        stride(from: 0, to: framed.count, by: maxPayload).map { start in
            let chunk = framed[start..<min(start + maxPayload, framed.count)]
            var report = [marker, UInt8(chunk.count)] + chunk
            report += Array(repeating: 0, count: reportSize - report.count)
            return report
        }
    }

    /// Payload of one 0xF2 report, nil for any other report
    static func payload(of report: [UInt8]) -> [UInt8]? {
        guard report.count >= 2, report[0] == marker else { return nil }
        let length = min(Int(report[1]), report.count - 2)
        return Array(report[2..<2 + length])
    }
}

// MARK: - Framing

enum StudioFraming {
    static let startOfFrame: UInt8 = 0xAB
    static let escape: UInt8 = 0xAC
    static let endOfFrame: UInt8 = 0xAD

    static func frame(_ message: [UInt8]) -> [UInt8] {
        var framed = [startOfFrame]
        for byte in message {
            if byte == startOfFrame || byte == escape || byte == endOfFrame {
                framed.append(escape)
            }
            framed.append(byte)
        }
        framed.append(endOfFrame)
        return framed
    }

    /// Reassembles messages from a byte stream that may arrive in any chunks
    struct Decoder {
        private enum State { case idle, data, escaped }
        private var state = State.idle
        private var buffer: [UInt8] = []

        /// Feeds bytes and returns every message completed by them
        mutating func feed(_ bytes: [UInt8]) -> [[UInt8]] {
            var messages: [[UInt8]] = []
            for byte in bytes {
                switch state {
                case .idle:
                    if byte == startOfFrame {
                        buffer = []
                        state = .data
                    }
                case .data:
                    switch byte {
                    case escape:
                        state = .escaped
                    case endOfFrame:
                        messages.append(buffer)
                        state = .idle
                    case startOfFrame:
                        // Unescaped SOF: drop the broken frame, start over
                        buffer = []
                    default:
                        buffer.append(byte)
                    }
                case .escaped:
                    buffer.append(byte)
                    state = .data
                }
            }
            return messages
        }
    }
}

// MARK: - Protobuf

/// Minimal protobuf encoder for the few request messages we send
struct ProtoWriter {
    private(set) var bytes: [UInt8] = []

    mutating func varint(_ field: Int, _ value: UInt64) {
        tag(field, wireType: 0)
        appendVarint(value)
    }

    mutating func bool(_ field: Int, _ value: Bool) {
        varint(field, value ? 1 : 0)
    }

    /// sint32, zigzag encoded
    mutating func sint32(_ field: Int, _ value: Int32) {
        varint(field, UInt64(UInt32(bitPattern: (value << 1) ^ (value >> 31))))
    }

    mutating func bytes(_ field: Int, _ value: [UInt8]) {
        tag(field, wireType: 2)
        appendVarint(UInt64(value.count))
        bytes += value
    }

    mutating func string(_ field: Int, _ value: String) {
        bytes(field, Array(value.utf8))
    }

    mutating func message(_ field: Int, _ build: (inout ProtoWriter) -> Void) {
        var nested = ProtoWriter()
        build(&nested)
        bytes(field, nested.bytes)
    }

    private mutating func tag(_ field: Int, wireType: UInt64) {
        appendVarint(UInt64(field) << 3 | wireType)
    }

    private mutating func appendVarint(_ value: UInt64) {
        var value = value
        while value >= 0x80 {
            bytes.append(UInt8(value & 0x7F) | 0x80)
            value >>= 7
        }
        bytes.append(UInt8(value))
    }
}

/// Minimal protobuf decoder: collects the fields of one message, nested
/// messages are decoded on demand
struct ProtoMessage {
    enum Value {
        case varint(UInt64)
        case bytes([UInt8])
        case fixed32(UInt32)
        case fixed64(UInt64)
    }

    private var fields: [Int: [Value]] = [:]

    init(_ bytes: [UInt8]) throws {
        var index = 0
        while index < bytes.count {
            let key = try Self.readVarint(bytes, &index)
            let field = Int(key >> 3)
            let value: Value
            switch key & 0x7 {
            case 0:
                value = .varint(try Self.readVarint(bytes, &index))
            case 1:
                guard index + 8 <= bytes.count else { throw StudioError.malformedMessage }
                value = .fixed64((0..<8).reduce(UInt64(0)) { $0 | UInt64(bytes[index + $1]) << (8 * $1) })
                index += 8
            case 2:
                let length = Int(try Self.readVarint(bytes, &index))
                guard length >= 0, index + length <= bytes.count else { throw StudioError.malformedMessage }
                value = .bytes(Array(bytes[index..<index + length]))
                index += length
            case 5:
                guard index + 4 <= bytes.count else { throw StudioError.malformedMessage }
                value = .fixed32((0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[index + $1]) << (8 * $1) })
                index += 4
            default:
                throw StudioError.malformedMessage
            }
            fields[field, default: []].append(value)
        }
    }

    func has(_ field: Int) -> Bool {
        fields[field] != nil
    }

    func uint(_ field: Int) -> UInt64 {
        guard case let .varint(value)? = fields[field]?.last else { return 0 }
        return value
    }

    func uint32(_ field: Int) -> UInt32 {
        UInt32(truncatingIfNeeded: uint(field))
    }

    /// sint32 fields use zigzag encoding
    func sint32(_ field: Int) -> Int32 {
        let raw = UInt32(truncatingIfNeeded: uint(field))
        return Int32(bitPattern: (raw >> 1) ^ (0 &- (raw & 1)))
    }

    func string(_ field: Int) -> String {
        guard case let .bytes(value)? = fields[field]?.last else { return "" }
        return String(decoding: value, as: UTF8.self)
    }

    func message(_ field: Int) throws -> ProtoMessage? {
        guard case let .bytes(value)? = fields[field]?.last else { return nil }
        return try ProtoMessage(value)
    }

    func messages(_ field: Int) throws -> [ProtoMessage] {
        try (fields[field] ?? []).compactMap { value in
            guard case let .bytes(bytes) = value else { return nil }
            return try ProtoMessage(bytes)
        }
    }

    /// Repeated uint32, packed (proto3 default) or not
    func uint32s(_ field: Int) throws -> [UInt32] {
        var result: [UInt32] = []
        for value in fields[field] ?? [] {
            switch value {
            case let .varint(raw):
                result.append(UInt32(truncatingIfNeeded: raw))
            case let .bytes(packed):
                var index = 0
                while index < packed.count {
                    result.append(UInt32(truncatingIfNeeded: try Self.readVarint(packed, &index)))
                }
            default:
                break
            }
        }
        return result
    }

    private static func readVarint(_ bytes: [UInt8], _ index: inout Int) throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
            guard shift < 64 else { break }
        }
        throw StudioError.malformedMessage
    }
}

// MARK: - Requests

/// The read-only requests the viewer sends (zmk.studio.Request)
enum StudioRequest: Equatable {
    case getDeviceInfo
    case getLockState
    case getKeymap
    case getPhysicalLayouts
    case listAllBehaviors
    case getBehaviorDetails(id: UInt32)

    func encoded(requestID: UInt32) -> [UInt8] {
        var writer = ProtoWriter()
        writer.varint(1, UInt64(requestID))
        switch self {
        case .getDeviceInfo:
            writer.message(3) { $0.bool(1, true) }
        case .getLockState:
            writer.message(3) { $0.bool(2, true) }
        case .getKeymap:
            writer.message(5) { $0.bool(1, true) }
        case .getPhysicalLayouts:
            writer.message(5) { $0.bool(6, true) }
        case .listAllBehaviors:
            writer.message(4) { $0.bool(1, true) }
        case let .getBehaviorDetails(id):
            writer.message(4) { request in
                request.message(2) { $0.varint(1, UInt64(id)) }
            }
        }
        return writer.bytes
    }
}

// MARK: - Responses

enum StudioError: Error, Equatable {
    case malformedMessage
    case unexpectedResponse
    /// The keyboard needs &studio_unlock before it shares its keymap
    case locked
    /// zmk.meta.ErrorConditions
    case device(code: UInt64)
    case timeout
    case notConnected
}

enum StudioLockState: Equatable {
    case locked
    case unlocked
}

struct StudioBinding: Equatable {
    let behaviorID: Int32
    let param1: UInt32
    let param2: UInt32
}

struct StudioLayer: Equatable {
    let id: UInt32
    let name: String
    let bindings: [StudioBinding]
}

/// Position and size in hundredths of a key unit
struct StudioKeyAttributes: Equatable {
    let width: Int32
    let height: Int32
    let x: Int32
    let y: Int32
}

struct StudioPhysicalLayout: Equatable {
    let name: String
    let keys: [StudioKeyAttributes]
}

enum StudioParameterKind: Equatable {
    case none
    case hidUsage
    case layer
    case number
}

struct StudioBehavior: Equatable {
    let id: UInt32
    let displayName: String
    /// Kinds of param1 and param2, from the first parameter set of the metadata
    let param1: StudioParameterKind
    let param2: StudioParameterKind
}

/// A decoded zmk.studio.Response
enum StudioResponse: Equatable {
    case requestResponse(id: UInt32, StudioResult)
    /// Unsolicited message; lockState is set when the lock state changed
    case notification(lockState: StudioLockState?)
}

enum StudioResult: Equatable {
    case error(code: UInt64)
    case noResponse
    case deviceInfo(name: String)
    case lockState(StudioLockState)
    case keymap([StudioLayer])
    case physicalLayouts(active: Int, layouts: [StudioPhysicalLayout])
    case behaviorIDs([UInt32])
    case behavior(StudioBehavior)
}

extension StudioResponse {
    static func decode(_ bytes: [UInt8]) throws -> StudioResponse {
        let response = try ProtoMessage(bytes)
        guard let requestResponse = try response.message(1) else {
            guard let notification = try response.message(2) else { throw StudioError.unexpectedResponse }
            guard let core = try notification.message(2), core.has(1) else { return .notification(lockState: nil) }
            return .notification(lockState: core.uint(1) == 1 ? .unlocked : .locked)
        }
        let id = requestResponse.uint32(1)

        if let meta = try requestResponse.message(2) {
            return .requestResponse(id: id, meta.has(2) ? .error(code: meta.uint(2)) : .noResponse)
        }
        if let core = try requestResponse.message(3) {
            if let info = try core.message(1) {
                return .requestResponse(id: id, .deviceInfo(name: info.string(1)))
            }
            if core.has(2) {
                return .requestResponse(id: id, .lockState(core.uint(2) == 1 ? .unlocked : .locked))
            }
        }
        if let behaviors = try requestResponse.message(4) {
            if let list = try behaviors.message(1) {
                return .requestResponse(id: id, .behaviorIDs(try list.uint32s(1)))
            }
            if let details = try behaviors.message(2) {
                return .requestResponse(id: id, .behavior(try decodeBehavior(details)))
            }
            // An empty list encodes as an empty message
            if behaviors.has(1) { return .requestResponse(id: id, .behaviorIDs([])) }
        }
        if let keymap = try requestResponse.message(5) {
            if let map = try keymap.message(1) {
                return .requestResponse(id: id, .keymap(try map.messages(1).map(decodeLayer)))
            }
            if let layouts = try keymap.message(6) {
                return .requestResponse(id: id, .physicalLayouts(
                    active: Int(layouts.uint(1)),
                    layouts: try layouts.messages(2).map(decodePhysicalLayout)
                ))
            }
        }
        throw StudioError.unexpectedResponse
    }

    private static func decodeLayer(_ layer: ProtoMessage) throws -> StudioLayer {
        StudioLayer(
            id: layer.uint32(1),
            name: layer.string(2),
            bindings: try layer.messages(3).map { binding in
                StudioBinding(behaviorID: binding.sint32(1), param1: binding.uint32(2), param2: binding.uint32(3))
            }
        )
    }

    private static func decodePhysicalLayout(_ layout: ProtoMessage) throws -> StudioPhysicalLayout {
        StudioPhysicalLayout(
            name: layout.string(1),
            keys: try layout.messages(2).map { key in
                StudioKeyAttributes(width: key.sint32(1), height: key.sint32(2), x: key.sint32(3), y: key.sint32(4))
            }
        )
    }

    private static func decodeBehavior(_ details: ProtoMessage) throws -> StudioBehavior {
        let firstSet = try details.messages(3).first
        func kind(_ field: Int) throws -> StudioParameterKind {
            let descriptions = try firstSet?.messages(field) ?? []
            guard !descriptions.isEmpty else { return .none }
            // A parameter may allow several value types; HID usage and layer win
            if descriptions.contains(where: { $0.has(5) }) { return .hidUsage }
            if descriptions.contains(where: { $0.has(6) }) { return .layer }
            if descriptions.allSatisfy({ $0.has(2) }) { return .none }
            return .number
        }
        return StudioBehavior(
            id: details.uint32(1),
            displayName: details.string(2),
            param1: try kind(1),
            param2: try kind(2)
        )
    }
}
