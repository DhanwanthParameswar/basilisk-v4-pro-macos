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

let probes: [(String, UInt8, UInt8, UInt8, [UInt8])] = [
 ("poll C0 q0", 0x00,0xC0,0x01,[0x00]), ("poll C0 q1", 0x00,0xC0,0x02,[0x01]), ("poll C2", 0x00,0xC2,0x01,[]),
 ("devmode", 0x00,0x84,0x02,[]),
 ("dpi stages", 0x04,0x86,0x26,[0x01]),
 ("dpi stages vs0", 0x04,0x86,0x26,[0x00]),
 ("charging", 0x07,0x84,0x02,[]), ("idle", 0x07,0x83,0x02,[]), ("lowbatt", 0x07,0x82,0x01,[]),
 ("scroll mode", 0x02,0x94,0x02,[0x01]), ("scroll accel", 0x02,0x96,0x02,[0x01]), ("smartreel", 0x02,0x97,0x02,[0x01]),
 ("bright logo", 0x0F,0x84,0x03,[0x01,0x04]), ("bright wheel", 0x0F,0x84,0x03,[0x01,0x01]), ("bright strip", 0x0F,0x84,0x03,[0x01,0x0A]), ("bright all", 0x0F,0x84,0x03,[0x01,0x00]),
 ("effect logo", 0x0F,0x82,0x0C,[0x01,0x04]),
 ("lod", 0x0B,0x85,0x04,[0x00,0x04]),
]
for (n,c,m,s,a) in probes { if let r = xfer(0x1f,c,m,s,a) { print(n.padding(toLength:15,withPad:" ",startingAt:0), "st", r[0], "|", hex(r[5..<(8+max(Int(r[5]),4))])) } }
