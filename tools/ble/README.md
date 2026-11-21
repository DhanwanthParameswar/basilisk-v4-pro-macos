# BLE probe (CoreBluetooth reference)

Working reference for talking to the Basilisk V4 Pro over Bluetooth on macOS.

Build (needs the embedded Info.plist so CoreBluetooth doesn't abort, and Bluetooth permission):
    swiftc -O ble_probe.swift -o ble_probe -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Info.plist

Run it from a real Terminal (so macOS can prompt for Bluetooth permission — click Allow).

Key pattern it demonstrates:
- retrieveConnectedPeripherals(withServices:[CBUUID("180F")]) to get the HID-hidden mouse by its Battery service
- connect, discover service 52401523-..., char1 (write) / char2 (notify)
- request = 8-byte header [0,argLen_lo,argLen_hi,0,class,id,0,0] + argLen arg bytes
- response = header [0,dataLen_lo,dataLen_hi,0,0,0,0,status] + dataLen data bytes (status byte 7)
See ../../TRANSPORTS.md.
