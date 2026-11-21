import Foundation

enum TransportKind: String, Sendable {
    case usb = "USB"
    case dongle = "HyperSpeed"
    case bluetooth = "Bluetooth"

    var symbol: String {
        switch self {
        case .usb: "cable.connector"
        case .dongle: "antenna.radiowaves.left.and.right"
        case .bluetooth: "dot.radiowaves.right"
        }
    }

    var longName: String {
        switch self {
        case .usb: "Wired (USB)"
        case .dongle: "HyperSpeed Wireless"
        case .bluetooth: "Bluetooth"
        }
    }
}

enum TransportError: LocalizedError, Sendable {
    case notConnected
    case timeout
    case unsupported
    case failed
    case io(Int32)

    var errorDescription: String? {
        switch self {
        case .notConnected: "The mouse isn't connected."
        case .timeout: "The mouse didn't answer in time."
        case .unsupported: "This setting isn't available over the current connection."
        case .failed: "The mouse rejected the command."
        case .io(let code): String(format: "USB error 0x%08x", code)
        }
    }
}

/// A link to the mouse. Wired and dongle share `HIDTransport`; Bluetooth uses `BLETransport`.
protocol RazerTransport: AnyObject, Sendable {
    var kind: TransportKind { get }
    /// Command classes this link can carry (Bluetooth only exposes a subset — see TRANSPORTS.md).
    func supports(_ cls: UInt8) -> Bool
    func send(_ cmd: RazerCommand) async throws -> RazerResponse
    func close()
}

extension RazerTransport {
    func supports(_ cls: UInt8) -> Bool { true }
}
