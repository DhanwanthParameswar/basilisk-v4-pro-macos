import Foundation
import IOKit.hid

func crc(_ r: [UInt8]) -> UInt8 { var c: UInt8 = 0; for i in 2..<88 { c ^= r[i] }; return c }
func makeReport(tx: UInt8, cls: UInt8, cmd: UInt8, size: UInt8, args: [UInt8] = []) -> [UInt8] {
    var r = [UInt8](repeating: 0, count: 90)
    r[1] = tx; r[5] = size; r[6] = cls; r[7] = cmd
    for (i, a) in args.enumerated() { r[8 + i] = a }
    r[88] = crc(r); return r
}
let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(mgr, [kIOHIDVendorIDKey: 0x1532] as CFDictionary)
IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
let devs = (IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice>) ?? []
guard let dev = devs.first(where: { (IOHIDDeviceGetProperty($0, kIOHIDMaxFeatureReportSizeKey as CFString) as? Int) == 90 }) else { print("no control iface"); exit(1) }
print("open:", IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone)))
func xfer(_ tx: UInt8, _ cls: UInt8, _ cmd: UInt8, _ size: UInt8, _ args: [UInt8] = []) -> [UInt8]? {
    var req = makeReport(tx: tx, cls: cls, cmd: cmd, size: size, args: args)
    let s = IOHIDDeviceSetReport(dev, kIOHIDReportTypeFeature, 0, &req, req.count)
    guard s == kIOReturnSuccess else { print(String(format: "set err 0x%08x", s)); return nil }
    usleep(60_000)
    var resp = [UInt8](repeating: 0, count: 90); var len = 90
    let g = IOHIDDeviceGetReport(dev, kIOHIDReportTypeFeature, 0, &resp, &len)
    guard g == kIOReturnSuccess else { print(String(format: "get err 0x%08x", g)); return nil }
    return resp
}
func hex(_ b: ArraySlice<UInt8>) -> String { b.map { String(format: "%02x", $0) }.joined(separator: " ") }
for tx: UInt8 in [0x1f, 0x3f, 0xff] {
    print(String(format: "== tx 0x%02x", tx))
    if let r = xfer(tx, 0x00, 0x81, 0x02) { print("firmware:", hex(r[0..<12])) }
    if let r = xfer(tx, 0x00, 0x82, 0x16) { print("serial:", String(bytes: r[8..<30].filter { $0 > 0 }, encoding: .ascii) ?? "?", "status", r[0]) }
    if let r = xfer(tx, 0x04, 0x85, 0x07, [0x01]) { print("dpi:", hex(r[0..<16])) }
    if let r = xfer(tx, 0x00, 0x85, 0x01) { print("polling:", hex(r[0..<10])) }
    if let r = xfer(tx, 0x07, 0x80, 0x02) { print("battery:", hex(r[0..<10])) }
}
