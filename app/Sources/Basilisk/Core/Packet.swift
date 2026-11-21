import Foundation

/// Status byte the firmware returns in byte 0 of every response.
enum RazerStatus: UInt8, Sendable {
    case new = 0, busy = 1, ok = 2, failure = 3, timeout = 4, unsupported = 5
}

/// One Razer protocol-2.5 command: class + id + argument bytes.
/// `size` is the data-size byte the firmware expects (see DATASHEET.md / PROTOCOL.md).
struct RazerCommand: Hashable, Sendable, CustomStringConvertible {
    let cls: UInt8
    let id: UInt8
    let size: UInt8
    var args: [UInt8]

    init(_ cls: UInt8, _ id: UInt8, size: UInt8, _ args: [UInt8] = []) {
        self.cls = cls; self.id = id; self.size = size; self.args = args
    }

    var isGet: Bool { id & 0x80 != 0 }
    var description: String { String(format: "%02x:%02x", cls, id) }
}

/// Decoded response. `args` are the argument bytes (byte 8 onward of the USB packet,
/// or the data payload of a BLE response) — identical layout on every transport.
struct RazerResponse: Sendable {
    let status: RazerStatus
    let cls: UInt8
    let id: UInt8
    let args: [UInt8]

    subscript(i: Int) -> UInt8 { i < args.count ? args[i] : 0 }

    func u16(_ i: Int) -> Int { Int(self[i]) << 8 | Int(self[i + 1]) }
}

/// The 90-byte USB feature-report packet.
/// `[status, txid, 0, 0, 0, size, class, id, args…(80), crc, 0]`, crc = XOR of bytes 2…87.
enum RazerPacket {
    static let length = 90

    static func encode(_ c: RazerCommand, transaction: UInt8) -> [UInt8] {
        var p = [UInt8](repeating: 0, count: length)
        p[1] = transaction
        p[5] = c.size
        p[6] = c.cls
        p[7] = c.id
        for (i, a) in c.args.prefix(80).enumerated() { p[8 + i] = a }
        p[88] = crc(p)
        return p
    }

    static func decode(_ p: [UInt8]) -> (transaction: UInt8, response: RazerResponse)? {
        guard p.count >= length, let status = RazerStatus(rawValue: p[0]) else { return nil }
        let n = min(Int(p[5]), 80)
        let args = Array(p[8..<(8 + max(n, 0))])
        return (p[1], RazerResponse(status: status, cls: p[6], id: p[7], args: args))
    }

    static func crc(_ p: [UInt8]) -> UInt8 {
        var c: UInt8 = 0
        for i in 2..<88 { c ^= p[i] }
        return c
    }
}
