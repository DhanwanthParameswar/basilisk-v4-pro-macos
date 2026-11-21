# Firmware analysis — Basilisk V4 Pro

All static. The updater is never run; the mouse is never flashed.

## Two corrections to earlier assumptions
1. **Not encrypted.** The bundled firmware is plaintext, embedded in the updater's .NET resources as raw
   byte-arrays. The .NET updater has no crypto. `encryption_en=1` / `.enc` belong only to an *online* update
   path that this package doesn't use.
2. **Not Airoha.** `ab1623m_evk` / `dfu1620-hid.dll` / the `0x08102000` region are **generic scaffolding** in
   Razer's multi-device "Customer FWU" framework — none of those strings appear in the actual V4 Pro images.
   Both the mouse and its dongle run **Nordic nRF54**.

## Verified device / firmware metadata (from `DeviceUpdater.resources`)
| | Mouse | Dongle |
|---|---|---|
| USB PID (normal) | **00E2** (Suit2) | **00E3** (Suit1) |
| Bootloader PID / ver | 1532:**110E** / 2.0 | 1532:110E / 2.0 |
| App FW version | **1.03.00** | 1.03.00 |
| App image size | **434,860 B** | 130,840 B |
| Feature report length | **91** (90 + report id) | 91 |
| Secondary "Flash FW" | v1.02.00 (type 5, not updated this run) | — |

**Completeness check: PASS.** The assembled `Suit2FWData` chunks equal the declared `Suit2FWFileSize`
(434,860) exactly → `mouse_00E2_fw.bin` is the **complete, current (v1.03.00) mouse application firmware**.
(The mouse's own MCUboot bootloader is not shipped in the updater — only the app image is.)

## Silicon (from strings in the images)
- **Nordic nRF54LM20A** (`nrf54lm20a`), Cortex-M33.
- **Zephyr RTOS** + Nordic **SoftDevice Controller** (`bt_hci_sdc`, `SoftDevice`) for Bluetooth LE.
- USB High-Speed peripheral (`usbhs@5a000`) — the wired / 8000 Hz path.
- Nordic **Fuel Gauge** for battery; `nrfx` HAL; **GRTC** timer (nRF54 feature).
- Razer board codename **"dragoon"** (`dragoon/libs/...`).

## Extracted images (plaintext, this folder)
| File | Device | Size | SP / Reset | Role |
|---|---|---|---|---|
| `mouse_00E2_fw.bin` | mouse 00E2 | 434,860 | `0x2001ae40` / `0x62ddd` | nRF54 Zephyr application (complete) |
| `dongle_00E3_fw.bin` | dongle 00E3 | 130,840 | `0x20007050` / `0x32585` | nRF54 Zephyr application |
| `mouse_fw_strings.txt` | — | — | — | mined strings |

## Capabilities the firmware confirms first-hand
- BLE HID over GATT (HOGP): multiple HID instances `hid_0..hid_3` / `hid_dev_0..2` = multi-host pairing.
- Bonding, whitelist/accept-filter advertising, SMP security, directed + regular advertising.
- Battery: Nordic Fuel Gauge; charger states trickle / CC / CV / complete.
- Radio: runtime-adjustable TX output power (dBm).
- "slot button" short/long press → the profile-slot / mode button.
- USB-HS wired device.

## Deconstruction status
Plaintext Cortex-M33 image in hand → full disassembly is possible. Goal: locate the HID feature-report
handler and its command-class dispatch to enumerate every class/id the firmware implements (write-only and
factory commands included). See `firmware/disasm/` as that proceeds.
