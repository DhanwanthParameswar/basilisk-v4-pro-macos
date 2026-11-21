import Foundation
import CoreBluetooth

/// Bluetooth LE transport.
///
/// macOS hides the mouse's HID-over-GATT service from CoreBluetooth, but it still exposes the
/// standard Battery service and Razer's vendor service. So we retrieve the already-paired mouse by
/// its Battery service (0x180F), connect, and use the vendor service:
///   52401524-… write  = command in   (char1)
///   52401525-… notify = response out (char2)
/// Framing (verified on hardware): request = 8-byte header [0, argLen lo, argLen hi, 0, class, id, 0, 0]
/// followed by argLen arg bytes (≥1; a zero-length frame is never processed). Response = an 8-byte
/// header [0, dataLen lo, dataLen hi, 0, 0, 0, 0, status] followed by dataLen data bytes.
/// Over Bluetooth the firmware only serves device-info, profile and class-0x10 commands.
final class BLETransport: NSObject, RazerTransport, @unchecked Sendable {
    static let service = CBUUID(string: "52401523-F97C-7F90-0E7F-6C6F4E36DB1C")
    static let commandChar = CBUUID(string: "52401524-F97C-7F90-0E7F-6C6F4E36DB1C")
    static let responseChar = CBUUID(string: "52401525-F97C-7F90-0E7F-6C6F4E36DB1C")
    static let batteryService = CBUUID(string: "180F")
    static let batteryLevelChar = CBUUID(string: "2A19")

    let kind: TransportKind = .bluetooth

    /// Called on the main queue.
    var onReady: ((BLETransport) -> Void)?
    var onDisconnect: (() -> Void)?
    var onBattery: ((Int) -> Void)?

    private var central: CBCentralManager!
    private let queue = DispatchQueue(label: "basilisk.ble")
    private var peripheral: CBPeripheral?
    private var commandChar: CBCharacteristic?
    private var ready = false
    private var retryTimer: DispatchSourceTimer?

    // One command in flight at a time.
    private let gate = DispatchSemaphore(value: 1)
    private var pending: CheckedContinuation<RazerResponse, Error>?
    private var pendingCmd: RazerCommand?
    private var sequence = 0
    private var responseHeader: [UInt8]?
    private var responseData: [UInt8] = []

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: queue)
    }

    func supports(_ cls: UInt8) -> Bool { [0x00, 0x05, 0x10].contains(cls) }

    func send(_ cmd: RazerCommand) async throws -> RazerResponse {
        guard supports(cmd.cls) else { throw TransportError.unsupported }
        await withCheckedContinuation { c in DispatchQueue.global().async { self.gate.wait(); c.resume() } }
        defer { gate.signal() }
        return try await withCheckedThrowingContinuation { cont in
            queue.async {
                guard self.ready, let p = self.peripheral, let ch = self.commandChar else {
                    cont.resume(throwing: TransportError.notConnected); return
                }
                self.sequence &+= 1
                let mine = self.sequence
                self.pending = cont
                self.pendingCmd = cmd
                self.responseHeader = nil
                self.responseData = []
                let args = cmd.args.isEmpty ? [UInt8(0)] : cmd.args
                let header: [UInt8] = [0, UInt8(args.count & 0xFF), UInt8(args.count >> 8), 0, cmd.cls, cmd.id, 0, 0]
                p.writeValue(Data(header), for: ch, type: .withResponse)
                p.writeValue(Data(args), for: ch, type: .withResponse)
                self.queue.asyncAfter(deadline: .now() + 2.0) {
                    guard self.sequence == mine else { return }
                    self.finish(.failure(TransportError.timeout))
                }
            }
        }
    }

    func close() {
        queue.async {
            self.retryTimer?.cancel()
            if let p = self.peripheral { self.central.cancelPeripheralConnection(p) }
            self.ready = false
        }
    }

    // MARK: - Private (on `queue`)

    private func finish(_ result: Result<RazerResponse, Error>) {
        guard let cont = pending else { return }
        pending = nil
        pendingCmd = nil
        cont.resume(with: result)
    }

    private func findMouse() {
        guard central.state == .poweredOn, peripheral == nil else { return }
        let candidates = central.retrieveConnectedPeripherals(withServices: [Self.batteryService])
        if let mouse = candidates.first(where: {
            let n = ($0.name ?? "").uppercased()
            return n.contains("BSK") || n.contains("BASILISK")
        }) {
            retryTimer?.cancel()
            peripheral = mouse
            mouse.delegate = self
            central.connect(mouse)
        }
    }

    private func startRetrying() {
        retryTimer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: 3.0)
        t.setEventHandler { [weak self] in self?.findMouse() }
        t.resume()
        retryTimer = t
    }
}

extension BLETransport: CBCentralManagerDelegate, CBPeripheralDelegate {
    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        if c.state == .poweredOn { startRetrying() }
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        p.discoverServices([Self.service, Self.batteryService])
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        ready = false
        peripheral = nil
        commandChar = nil
        finish(.failure(TransportError.notConnected))
        DispatchQueue.main.async { self.onDisconnect?() }
        startRetrying()
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        peripheral = nil
        startRetrying()
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        for s in p.services ?? [] {
            if s.uuid == Self.service {
                p.discoverCharacteristics([Self.commandChar, Self.responseChar], for: s)
            } else if s.uuid == Self.batteryService {
                p.discoverCharacteristics([Self.batteryLevelChar], for: s)
            }
        }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for ch in s.characteristics ?? [] {
            switch ch.uuid {
            case Self.commandChar: commandChar = ch
            case Self.responseChar: p.setNotifyValue(true, for: ch)
            case Self.batteryLevelChar:
                p.readValue(for: ch)
                p.setNotifyValue(true, for: ch)
            default: break
            }
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor ch: CBCharacteristic, error: Error?) {
        guard ch.uuid == Self.responseChar, error == nil, commandChar != nil, !ready else { return }
        ready = true
        DispatchQueue.main.async { self.onReady?(self) }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard let value = ch.value else { return }
        let bytes = [UInt8](value)

        if ch.uuid == Self.batteryLevelChar, let level = bytes.first {
            DispatchQueue.main.async { self.onBattery?(Int(level)) }
            return
        }
        guard ch.uuid == Self.responseChar, let cmd = pendingCmd else { return }

        if responseHeader == nil {
            guard bytes.count >= 8 else { return }
            responseHeader = Array(bytes.prefix(8))
            let length = Int(bytes[1]) | Int(bytes[2]) << 8
            let status = RazerStatus(rawValue: bytes[7]) ?? .failure
            if status == .unsupported { finish(.failure(TransportError.unsupported)); return }
            if status == .failure { finish(.failure(TransportError.failed)); return }
            if length == 0 {
                finish(.success(RazerResponse(status: status, cls: cmd.cls, id: cmd.id, args: [])))
            }
            return
        }
        responseData += bytes
        let header = responseHeader!
        let length = Int(header[1]) | Int(header[2]) << 8
        if responseData.count >= length {
            let status = RazerStatus(rawValue: header[7]) ?? .ok
            finish(.success(RazerResponse(status: status, cls: cmd.cls, id: cmd.id, args: Array(responseData.prefix(length)))))
        }
    }
}
