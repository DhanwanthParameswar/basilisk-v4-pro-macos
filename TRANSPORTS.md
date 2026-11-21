# How the Mac talks to the Basilisk V4 Pro (connection matrix) — VERIFIED

Tri-mode device; the transports are **not** equivalent. All three now characterised, two tested live on-device.

| # | Connection | Enumerates as | Mac framework | Protocol | Command set | Status |
|---|-----------|---------------|---------------|----------|-------------|--------|
| 1 | **Wired USB-C** | USB `1532:00E2` | IOKit `IOHIDManager` | 91-byte HID **feature report**, 0xFF00 control interface | **FULL** (10 classes) | **Verified live** (read+write) |
| 2 | **HyperSpeed dongle** | USB `1532:00E3` | IOKit `IOHIDManager` | same feature report (relayed over 2.4 GHz) | **FULL** — identical to wired (DPI, buttons, power, lighting all returned OK live) | **Verified live** |
| 3 | **Bluetooth LE** | BLE `BSK V4 PRO` | **CoreBluetooth** | custom GATT, chunked framing (below) | **LIMITED** (see table) | **Verified live** |
| — | DFU bootloader | USB `1532:110E` | — | firmware update | n/a | out of scope |

## Bluetooth LE — verified details
- **Access on macOS:** the mouse is a BLE-HID device, so `retrieveConnectedPeripherals(withServices:[HID 0x1812])` returns
  nothing. Instead retrieve it by a **standard service it also has** — `180F` (Battery) works — then `connect` and
  discover. macOS exposes the vendor service even though it hides the HID service.
- **Vendor GATT service:** `52401523-F97C-7F90-0E7F-6C6F4E36DB1C`
  - `52401524-…` **command in** — write (char1)
  - `52401525-…` **response out** — notify (char2)
  - `52401526-…` char3 — notify
- **Framing (chunked, different from USB):**
  - **Request:** write an **8-byte header** `[00, argLen_lo, argLen_hi, 00, class, id, 00, 00]` to char1, then write
    `argLen` bytes of arguments (≥1 byte — send one `00` if the command takes none). A length-0 frame is NOT processed.
  - **Response:** two notifications on char2 — an 8-byte header `[00, dataLen_lo, dataLen_hi, 00,00,00,00, status]`
    (status at byte 7: **02=OK, 03=needs-args, 05=unsupported**), then `dataLen` bytes of data.
- **Live class coverage over BLE** (status from the real mouse):
  | class | result |
  |---|---|
  | 0x00 device/system | **OK** (returned fw v1.02) |
  | 0x05 profiles | **OK** |
  | 0x10 (undocumented) | handled (needs-args) |
  | 0x02 buttons, 0x04 DPI, 0x06 macros, 0x07 power | **unsupported** |
  | 0x0f lighting, 0x0b sensor, 0x15 hapticore | **unsupported** (for the ids tested) |

  → **Over Bluetooth you cannot change DPI, buttons, macros, or power.** Full configuration needs USB or the dongle.

## Dongle (2.4 GHz) — verified detail
Same 90-byte feature-report protocol and full command set as wired USB, but the link is **asynchronous**: a
command may return status **01 (busy)** or **04 (timeout)** for the first few polls while the dongle waits for
the mouse over RF, then the real **02 (OK)** response. The IOKit layer must **poll GetReport / retry** (≈20 ms
intervals, up to ~0.5 s) rather than expecting an immediate reply like wired. 8000 Hz polling is dongle-only.

## App architecture (confirmed by testing)
- **Two Mac backends behind one `Transport` protocol:**
  - **IOKitHIDTransport** — wired + dongle. Match VID `0x1532`, PID `0x00E2`/`0x00E3`, the 0xFF00 / 90-byte-feature interface. 90-byte packets. (Proven on USB.)
  - **BLETransport** — CoreBluetooth, the service/chars + chunked framing above. (Proven live.)
- A device manager detects the active link and **adapts the UI**: on Bluetooth, expose only device info + profiles and tell the user to connect USB/dongle for DPI/buttons/macros/power/lighting.
