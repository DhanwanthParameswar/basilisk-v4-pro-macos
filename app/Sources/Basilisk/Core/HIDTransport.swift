import Foundation
import IOKit.hid

/// Wired (1532:00E2) and HyperSpeed dongle (1532:00E3) transport.
/// Both expose the same 90-byte vendor feature report on the 0xFF00 control interface.
/// The dongle relays over 2.4 GHz, so replies arrive asynchronously (status busy/timeout
/// for a few polls) — we poll GetReport and resend on timeout instead of assuming an
/// immediate answer. All I/O runs on one serial queue so commands never interleave.
final class HIDTransport: RazerTransport, @unchecked Sendable {
    let kind: TransportKind
    let device: IOHIDDevice
    private let queue = DispatchQueue(label: "basilisk.hid", qos: .userInitiated)
    private var transaction: UInt8 = 0x10
    private var isOpen = false

    init(device: IOHIDDevice, kind: TransportKind) {
        self.device = device
        self.kind = kind
        isOpen = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess
    }

    func send(_ cmd: RazerCommand) async throws -> RazerResponse {
        try await withCheckedThrowingContinuation { cont in
            queue.async {
                cont.resume(with: Result { try self.transact(cmd) })
            }
        }
    }

    func close() {
        queue.sync {
            if isOpen { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }
            isOpen = false
        }
    }

    // MARK: - Private (runs on `queue`)

    private func nextTransaction() -> UInt8 {
        // Rotate the transaction id so a stale reply to a previous command can never match.
        transaction = transaction >= 0x7F ? 0x10 : transaction + 1
        return transaction
    }

    private func transact(_ cmd: RazerCommand) throws -> RazerResponse {
        guard isOpen else { throw TransportError.notConnected }
        let wireless = kind == .dongle
        let sends = wireless ? 4 : 2
        let polls = wireless ? 40 : 15
        let firstWait: useconds_t = wireless ? 12_000 : 3_000
        let pollWait: useconds_t = wireless ? 15_000 : 4_000

        for _ in 0..<sends {
            let tx = nextTransaction()
            var out = RazerPacket.encode(cmd, transaction: tx)
            let set = IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, 0, &out, out.count)
            if set != kIOReturnSuccess {
                if set == kIOReturnNotAttached || set == kIOReturnNoDevice { throw TransportError.notConnected }
                usleep(20_000)
                continue
            }
            usleep(firstWait)

            poll: for _ in 0..<polls {
                var inb = [UInt8](repeating: 0, count: RazerPacket.length)
                var len = CFIndex(RazerPacket.length)
                let get = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 0, &inb, &len)
                if get == kIOReturnSuccess,
                   let (rtx, resp) = RazerPacket.decode(inb),
                   rtx == tx, resp.cls == cmd.cls, resp.id == cmd.id {
                    switch resp.status {
                    case .ok: return resp
                    case .unsupported: throw TransportError.unsupported
                    case .failure: throw TransportError.failed
                    case .timeout: break poll          // dongle lost the RF round-trip → resend
                    case .busy, .new: break            // keep polling
                    }
                } else if get == kIOReturnNotAttached || get == kIOReturnNoDevice {
                    throw TransportError.notConnected
                }
                usleep(pollWait)
            }
        }
        throw TransportError.timeout
    }
}
