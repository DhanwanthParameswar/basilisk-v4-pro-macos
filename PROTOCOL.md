# Razer Basilisk V4 Pro — protocol map

Status: **in progress**. Sources, strongest first:

1. **Synapse 4 device middleware** for PID 226 (internal codename `DoloresT1`), pulled from the Synapse
   Service Worker cache in the Parallels VM (`apps.razer.com/synapse/products/226/mw/*`, build
   `master-29oct2026`). This gives command bytes, names and payload layouts from Razer's own code.
2. **Live read sweep** of 170 GET commands against the mouse (firmware 1.02, USB `1532:00E2`), run from
   the VM. See `captures/v4pro/support_matrix.txt`.
3. macOS read probes (`probe/probe.swift`).

Nothing below has been *written* to the mouse yet — every set command is still unverified on hardware.

## Transport

| | Value |
|---|---|
| USB IDs | `1532:00E2` (wired), `1532:00E3` (HyperSpeed dongle), `1532:00E4` (Bluetooth) |
| Control interface | Interface 3, usage page `0xFF00` inside a `0x0C/0x01` collection, one 90-byte feature report, no report ID |
| macOS | `IOHIDDeviceSetReport/GetReport(kIOHIDReportTypeFeature, 0, …, 90)` — works without any driver |
| Windows | `HidD_SetFeature/GetFeature` on `MI_03` (91 bytes incl. report ID 0) |
| Protocol family | `rzDevice25` (Razer protocol 2.5), dual-link device |

### Packet (90 bytes)

| Offset | Field |
|---|---|
| 0 | status — host sends 0; device returns 1 busy, 2 ok, 3 failure (bad args), 4 timeout, 5 not supported |
| 1 | transaction ID — `0x1F` works; Synapse uses its own (`0x1C` seen) |
| 2–4 | remaining packets / protocol type (0) |
| 5 | data size |
| 6 | command class |
| 7 | command ID (bit 7 set = GET, clear = SET) |
| 8–87 | arguments (arg0 is usually storage/profile: `0x00` = live/no-store, `0x01` = VARSTORE/profile 1) |
| 88 | CRC = XOR of bytes 2…87 |
| 89 | reserved |

## Command classes the V4 Pro answers

`[size, class, id]` triples are exactly as defined in Synapse. ✅ = mouse returned OK in the live sweep,
◐ = supported but needs different args (status 3).

### 0x00 — device / system
| Get | Set | Size | Name | Live |
|---|---|---|---|---|
| 00:81 | — | 2 | Firmware version | ✅ `01 02` = v1.02 |
| 00:82 | — | 22 | Serial number | ✅ |
| 00:84 | 00:04 | 2 | Device mode (0 normal, 3 driver) | ✅ currently 3 (Synapse holds driver mode) |
| 00:86 | 00:06 | 3 | Edition info (0 = black, 128 = White Edition) | ✅ |
| 00:87 | — | 4 | Extended firmware version | ✅ |
| 00:bb | — | 1 | On-dock charging status | ✅ |
| **00:c0** | **00:40** | 2 | **USB high-speed (HyperPolling) polling period** | ✅ `01 08` |
| 00:db | 00:5b | 1 | Tournament mode | ◐ |
| 00:85 | 00:05 | 1 | Legacy polling period | ❌ not supported — use 00:c0/00:40 |

Polling rates offered by Synapse for this mouse: 125 / 500 / 1000 / 2000 / 4000 / 8000 Hz
(8000 only through the HyperPolling dongle; `smartDimming` dims the LEDs at high rates).

### 0x02 — buttons and scroll wheel
| Get | Set | Size | Name | Live |
|---|---|---|---|---|
| 02:8e | 02:0c | 80 | Button assignment list / single button assignment | ✅ |
| 02:96 | 02:16 | 2 | Scroll virtual acceleration state | ✅ |
| 02:a2 | 02:22 | 2 | Scroll virtual acceleration level | ✅ |
| **02:b0** | **02:30** | 2 | **Scroll mode: Tactile / FreeSpin / MicroTactile** | ✅ currently 0 |
| — | 02:14 | 2 | Scroll free/notched (legacy) | — |
| — | 02:23 | 2 | Smart Reel threshold | — |
| — | 02:17 | 80 | Scroll mode auto-switch state | — |

### 0x15 — Hapticore / LK scroll wheel (undocumented publicly)
| Get | Set | Size | Name | Live |
|---|---|---|---|---|
| **15:8b** | **15:0b** | 2 | **Enabled wheel-mode bitmask** for the mode button (Tactile=1, FreeSpin=2, MicroTactile=4; at most two may be disabled) | no reply in sweep — retry with classId arg |
| 15:80 / 15:81 | — | 2 | Hapticore scroll profile active / max stage | ✅ |
| 15:82 / 15:83 / 15:84 | — | 80 | Hapticore tick setting / generator setting / generator table | ✅ |
| 15:87 | — | 9 | Hapticore scroll stage information | ✅ |

The firmware answers *every* 0x15 GET with status OK, so OK alone doesn't prove a command exists here.

### 0x04 — DPI
| Get | Set | Size | Name | Live |
|---|---|---|---|---|
| 04:85 | 04:05 | 7 | Active DPI: `[store, X hi, X lo, Y hi, Y lo, 0, 0]` | ✅ now 1600×1600 (Synapse applied its profile) |
| 04:86 | 04:06 | 80 | DPI stages: `[store, active stage, count, {id, X hi, X lo, Y hi, Y lo, 0, 0}×n]` | ✅ 5 stages |

### 0x05 / 0x06 — onboard profiles and macros
Supported: `05:80` profile count, `05:81` profile list, `05:84` active profile, `05:8c` profile color,
`06:89` / `06:8a` / `06:8b` / `06:8c` macro data / memory / ID list / name. Set counterparts: `05:02` create,
`05:03` delete, `05:04` set active, `05:08` name, `06:09` data, `06:03` delete, `06:08` allocate.

### 0x07 — power
| Get | Set | Size | Name | Live |
|---|---|---|---|---|
| 07:80 | — | 2 | Battery level (0–255) | ✅ `f0` ≈ 94% |
| 07:81 | 07:01 | 1 | Low-battery threshold | ✅ |
| 07:82 | 07:02 | 1 | Max LED brightness on battery | ✅ |
| 07:83 | 07:03 | 2 | Sleep timeout (seconds, big-endian) | ✅ 300 s |
| 07:84 | — | 2 | Charging status | ✅ charging |
| 07:93 | 07:13 | 3 | Smart illumination control | ✅ |

### 0x0B — sensor (lift-off, calibration, angle)
Supported: `0b:80`, `0b:85` configuration, `0b:90`–`0b:92` acceleration, `0b:94` angle tune, plus the
calibration family `0b:81`–`0b:8a`, `0b:93` (status 3 = need specific args). Used by the
`orca5PlusCalibrationEngine` (Smart Tracking / asymmetric lift-off).

### 0x0F — Chroma lighting (the old `03:xx` LED class is NOT supported)
| Get | Set | Size | Name | Live |
|---|---|---|---|---|
| 0f:80 | — | 80 | Region ID list | ✅ regions `01` wheel, `04` logo, `0a` side strip |
| 0f:81 | — | 80 | Effect ID list | ✅ `00 01 02 03 04 05 08` |
| 0f:82 | 0f:02 | 80 | Effect | ✅ |
| 0f:84 | 0f:04 | 3 | Brightness `[store, region, 0–255]` | ✅ (macOS probe) |
| — | 0f:03 | 80 | Custom frame (per-LED colors; what Synapse streams) | seen live |
| 0f:85 | 0f:05 | 5 | Chroma calibration | ✅ |
| 0f:98 | 0f:18 | 1 | Startup animation | ◐ |

LED layout (from Chroma SDK device file): wheel 1 LED, logo 1 LED, side strip 5 LEDs.

## Verified by sniffing Synapse (packets Synapse actually sent)

Method: the mouse keeps its last response in the feature report, and reading it doesn't consume it.
`probe/sniff.ps1` polls `HidD_GetFeature` in a tight loop inside the VM and logs every new response
(Synapse's 0F:03 lighting frames are filtered out) while Synapse is clicked through via computer use.

| Synapse control | Packet (class:id [args]) |
|---|---|
| Scroll mode Tactile / Free-Spin / Precision Tactile | `02:30 [01, 00 / 01 / 02]` |
| Disable-mode checkboxes | `15:0b [01, mask]`, mask bits Tactile=1, FreeSpin=2, Precision=4 (all enabled = 07). Disabling the active mode makes Synapse also send `02:30` to switch to the next enabled mode |
| Scroll acceleration on/off | `02:16 [01, 01/00]` |
| Scroll acceleration level low/med/high | `02:22 [01, 00/02/04]` |
| Smart-Reel on/off | `02:17 [01, 01/00, 0…]` (size 0x50) |
| Smart-Reel speed low/med/high | `02:23 [01, 00/02/04]` |
| Background polling by Synapse | `07:80 [00, level]`, `07:84 [00, charging]` about every 10 s |
| DPI stages | `04:06` size 0x26: `[01, activeStage(1-based), count, {id(0-based), Xhi, Xlo, Yhi, Ylo, 00, 00}×n]`. GET `04:86` returns ids 1-based |
| Sensitivity stages off | `04:06` size 0x0a: `[01, 01, 01, 00, Xhi, Xlo, Yhi, Ylo, 00, 00]` (one stage = current DPI) |
| Polling rate | `00:40 [01, 8000/Hz]` → 01=8000, 02=4000, 04=2000, 08=1000, 10=500, 40=125. Synapse reads back with `00:c0` |
| Brightness (all LEDs) | `0f:04 [01, 00, 0–255]`; toggle off = value 00 |
| Smart dimming | `07:13 [01, enabled, level]`, level 02=0%, 01=25%, 00=50% |
| Sleep timeout | `07:03 [hi, lo]` seconds BE, **no store byte** (60…900) |
| Low-power threshold | `07:01 [pct×255/100]` (5%=0d, 30%=4d, 100%=ff) |
| Smart Tracking (symmetric) | `0b:03 [00, 04, 01]` then `0b:0b [00, 04, 01, level]` level 00 low / 01 med / 02 high |
| Asymmetric cut-off | `0b:0b [00, 04, 04, 00]` then `0b:05 [00, 04, liftoff, landing, 0…]` (UI value − 1) |
| Dynamic sensitivity on/off | `0b:10 [01, 01/00]` |
| Dynamic sensitivity preset | `0b:11 [01, n]` Classic 0, Natural 1, Jump 2, Custom 3 |
| Custom curve | `0b:13` × 32 packets: `[01, 03, fa, offset, 08, {idx, f24}×8]`, f24 = float32 ratio with low byte dropped (`52 80 3f` = 1.0025); 250 points |
| Button remap | `02:0c [profile, buttonId, layer, fnId, n, data…]` (see Buttons below) |

Synapse-only (no packets, ignored for the native app): smart polling-rate switcher, switch-off-lighting on idle/display-off,
sensitivity matcher, all animated "quick effects" while Synapse runs (it holds driver mode `00:84 = 03`
and streams `0f:03` frames; on-board effects only come from `0f:02` with store=01).

## On-board lighting effects (`0f:02`)

Payload `[store, region, effectId, flags, rate, colorCount, R,G,B …]`. Regions: 00 all, 01 wheel, 04 logo, 0a strip.
Effect IDs the V4 Pro reports (`0f:81`): 00 Off, 01 Static, 02 Breathing, 03 Spectrum, 04 Wave, 05 Reactive, 08 Custom frame.

| Effect | flags | rate | colors |
|---|---|---|---|
| Static | 0 | 0 | 1 |
| Breathing | `speed ? 0 : colorCount` | speed or duration | 0 (random), 1 or 2 |
| Spectrum | 0 | speed | 0 |
| Wave | 1 = one direction, 2 = reverse | speed (1→75, 2→55, 3→40, 4→25, 5→15) | 0 |
| Reactive | 0 | duration | 1 |

## Buttons (`02:0c`)

Button IDs: 1 left, 2 right, 3 wheel click, 4 / 5 side, 9 / 10 scroll up/down, 52 / 53 tilt left/right,
14 profile button, 96 sensitivity-stage button, 106 scroll-mode toggle, 57 Hypershift, 128 AI Prompt.
Layer: 00 standard, 01 Hypershift. Onboard slots: 4.

Read back with `02:8c [01, buttonId, layer]` → `[01, buttonId, layer, fnId, len, data…]` ✅ verified for all 14 buttons on hardware (2026-11-21).

| fnId | Group | Data |
|---|---|---|
| 00 | Disabled | — |
| 01 | Mouse button | `[code]` 1 L, 2 R, 3 M, 4, 5, 9 up, 10 down, 52 left, 53 right ✅ verified (`02:0c 01 04 00 01 01 04`) |
| 02 | Keyboard key | `[modifierMask, HID usage]` |
| 03/04/05 | Macro once / N times / while held / toggle | `[macroId hi, lo, repeat]` |
| 06 | DPI | `[1]` up, `[2]` down, `[5, Xhi, Xlo, Yhi, Ylo]` clutch ✅ verified, `[6]` cycle up, `[7]` cycle down |
| 07 | Profile | `[1]` up, `[2]` down, `[3, id]` specific, `[4]` cycle up, `[5]` cycle down |
| 0a | Media key | consumer usage `[hi, lo]` |
| 0b | Double click | `[button]` |
| 0c | Hypershift | `[1]` |
| 0e | Turbo / repeating button | `[code, rate hi, lo]`, but the **length byte is 1**. Factory tilt = `0e 01 68 00 14` (0x68 scroll-left, 0x69 scroll-right, rate 20) ✅ read on hardware |
| 12 | Scroll-wheel mode | `[1]` cycle (factory scroll-mode button, ✅ read on hardware), `[2]` up, `[3]` down, `[4]` cycle up, `[5]` cycle down |
| 16 | Perfect 180 | `[direction, count hi, count lo, enabled]` ✅ verified (`… 16 04 00 07 d0 00`, count 2000) |

## Onboard memory (verified on hardware)

Multi-byte numbers are big-endian. 16-bit = `[hi, lo]`, 32-bit = `[b3, b2, b1, b0]`.
Use the **exact payload length** as the size byte (`n`); padding to 0x50 makes some writes fail with status 3.

### Profiles (class 05) — 5 slots (1 = default/white, 2–5 = red, green, blue, cyan)
| Cmd | Payload | Notes |
|---|---|---|
| `05:80` | → `[n]` | ✅ |
| `05:81` | → `[maxSlots=05, id, id…]` | ✅ `05 01` = only profile 1; `05 01 02` after creating slot 2 |
| `05:84` / `05:04` | `[id]` | get / set active profile ✅ read |
| `05:02` | `[id]` | create profile ✅ seen from Synapse |
| `05:03` | `[id]` | delete profile ✅ **written by us**, list confirmed |
| `05:0b` | `[id]` | reset profile |
| `05:0c` / `05:8c` | `[id, R, G, B]` | profile color |
| `05:08` / `05:88` | `[id, offset(2), total(2)=00fa, data…]`, ≤64 bytes per chunk, `n` = chunk + 5 | 250-byte header, read back ✅ |

Profile header (250 bytes): GUID 16 · UTF-8 name 100 · owner (ASCII Razer user id) 128 · key-mapping hash 6.
Profile 1 has no header. Every other command already takes the profile id as its first argument
(DPI `04:05/04:06`, polling `00:40`, scroll `02:17/02:30`, buttons `02:0c`…), so writing slot N = the
same commands with arg0 = N.

**Synapse "assign to slot" sequence** (captured): `05:02 [N]` → `00:40 [N, rate]` → `02:17 [N, …]` →
`05:08 ×4` header → `04:05 [N, dpi]` → `04:06 [N, stages]` → `02:0c` only for buttons that differ from
defaults. Clearing a slot = `05:03 [N]` then `06:8e`. Memory cost: 256 bytes per extra profile.

### Macros (class 06) — up to 100, ~304 KB
| Cmd | Payload | Notes |
|---|---|---|
| `06:8e` | → `[maxId(2)=0064, maxMem(4)=0004c000, available(4), recyclable(4)]` | ✅ storage info |
| `06:80` | → `[count]` | ✅ 0 → 1 → 0 |
| `06:8b` | `[offset(2)]` → id list | |
| `06:08` | `[id(2), size(4)]` | allocate ✅ |
| `06:0c` / `06:8c` | `[id(2), offset(2), total(2)=00fa, data ≤64]`, `n` = chunk + 6 | header ✅ (the last 58-byte chunk returns status 3, and Synapse ignores that too) |
| `06:09` / `06:89` | `[id(2), offset(4), len, data ≤72]`, `n` = len + 7 | macro data ✅ round-tripped |
| `06:03` | `[id(2)]` | delete ✅ |

Macro header (250 bytes): GUID 16 · item count (4, as two little-endian 16-bit words) · UTF-8 name 100 · 16 zero · timestamp 16 · hash 32 · 66 zero.
Space needed = ceil((dataSize + 256) / 256) × 256. Deleted macros become "recyclable" until storage is defragmented
(Synapse re-writes everything after a format).

Macro event stream (opcodes from Synapse's `macroItemToFWData`):
| Op | Bytes | Meaning |
|---|---|---|
| 01 / 02 | `[op, HID usage]` | key down / up |
| 03 / 04 | `[op, …]` | power key down / up |
| 05 / 06 | `[op, …]` | media key down / up |
| 08 | `[08, mask]` | mouse buttons: full state, bits L=1 R=2 M=4 B4=8 B5=16 |
| 0a | `[0a, 01 / ff]` | wheel up / down |
| 11 / 12 / 13 / 14 | delay in ms as 1 / 2 / 3 / 4 bytes | |
| 15 | `[15, Xhi, Xlo, Yhi, Ylo]` | cursor move |

Test macro used: `01 04 11 32 02 04` = A down, wait 50 ms, A up.

## Firmware command space (blind read sweep)

4,608 GETs (IDs 0x80–0xFF) across classes 00–20, 7F, FE, FF, sent with arg0 = 01 while Synapse was running.
Raw results: `captures/fullsweep_out.txt`.

**Caveats:** about 1/3 of the commands got no reply, because Synapse streams lighting frames on the same interface. Some
classes don't reject unknown IDs: class 06 and 15 answer `02` (echo) to everything, and 04/05/0B/0F/FE answer `03` to
almost everything. So for those classes "answered" doesn't prove a command exists. The clean signal comes from classes
that return `05` for unknown IDs: 00, 02, 07, 10.

**Classes the firmware implements:** 00, 02, 04, 05, 06, 07, 0B, 0F, **10 (new)**, 15, FE.
**Not implemented:** 01, 03 (legacy LED), 08, 09, 0A, 0C, 0D, 0E, 11–14, 16–20, 7F, FF.

**Real commands Synapse never uses** (clean classes, status 02):
| Cmd | Reply | Guess |
|---|---|---|
| `00:8d`, `00:b3` | zeros | |
| `00:97`, `00:a4` | `c3 f3 41 ca` ×3 + `01` | wireless/pairing addresses (dongle slots?) |
| `00:cd`, `00:cf` | status 03 | need args |
| `02:97` | `01 00` | Smart-Reel state read |
| `02:98` | `19` (25) | ? |
| `02:a3` | `01 02` | Smart-Reel threshold read |
| `02:b3` | `02 16 17 15 16 02 02` | scroll-wheel per-mode parameters? |
| `02:b4` | `02 cd cc 0c 40` | float32 2.2: a scroll/haptic constant |
| `04:83`, `04:84` | stages / `01 03` | alt DPI stage read / active stage |
| `05:8a` | `05` | max profile slots |
| `06:8d` | `01 00 00 00 88 46 00 20 f9 35…` | macro/flash memory map (contains RAM-like addresses) |
| `07:8d` | `01 00 28 01 9c 01 4f 05` | power telemetry (voltages/current?) |
| `0b:8e` | `04 00 00 00 08 12` | sensor info (sensor id 04, 0x1208?) |
| `10:83` | `01 00 00 00 00 40` | unknown class 0x10 |

## Hardware events (mouse → host, unsolicited)

Input reports parsed by Synapse's `rzHardwareEventsProtocol25Parser`. Byte 0 = record type:
02 media keys, 03 power keys, 04 Razer keys, **05 notification**, 08/09 the same via the dongle's secondary device,
4d calibration redirect, 5a calibration Z/Q data, 68 profile-cycle button.

Notification (`05`): byte 1 = event, then data:
| Event | Data |
|---|---|
| 01 profile change | `[profileId]` |
| 02 DPI change | `[Xhi, Xlo, Yhi, Ylo, Zhi, Zlo]` |
| 05 / 06 lifted / put down | — |
| 08 brightness change | `[value]` |
| 09 wireless change | `[state, type]` |
| 0a calibration change | `[value]` |
| 0c external power change | `[value]` |
| 17 auto-sleep change | |
| 31 battery change | `[level/255, charging, powerSource, deviceType]` |
| 35 wireless change v2 | `[state, type, PID hi, lo]` |
| 38 active connection change | `[type, connected]` |
| 39 scroll free/notch mode change | `[mode]` |
| 3a Hapticore scroll stage change | |
| 41 battery fully charged | |
| 46 button change | `[type, mode]` |

Not yet confirmed which HID interface carries these on macOS. Most likely the 16-byte input report on the
keyboard-type interface (`MaxInputReportSize 16`).

## How Synapse 4 is built (what the code showed)

| Layer | Where | Readable? |
|---|---|---|
| Shell | `RazerAppEngine` (Electron, x64), `resources/app.asar` | yes, plain JS |
| Transport | `electron/UsbRzDeviceAction.js` → native `node-rz-hid` (`sendFeatureReport` / `getFeatureReport`, `claimInterface: 3`), status/echo check in `Protocol/protocol25.js` | JS yes; the `.node` addon is native |
| Device logic | Web bundle downloaded per product: `apps.razer.com/synapse/products/226/mw/*` (Service Worker cache) | yes, minified but not obfuscated; all names kept |
| Command library | chunk `7846`: every protocol-2.5 command (`[size, class, id]` + name), `rzDevice25` methods, OBM engine, macro encoder, generic features | yes |
| Device config | `products/226/mw/main.*.js`: feature flags, button table, defaults, PIDs | yes |
| UI | `products/226/ui/*` (React) | yes, but software only |
| Lighting | Chroma SDK services (x86 native: `RzSDKService`, `RzDeviceManager`…) stream `0f:03` frames | native, not needed |
| Software remap | `RzDevU_00e2` kernel filter drivers (x64) | native, can't load on ARM64, not needed for on-board features |
| Cloud | profiles synced to the Razer ID account | not needed |

## USB IDs
`00E2` wired, `00E3` HyperSpeed dongle, `00E4` Bluetooth (`claimInterface: 3`).

## V4 Pro-specific features (from Synapse's feature declaration)

- `perfect180Feature` — a button-mapping group (`Perfect180Group`) plus a per-game list. Bytes TBD.
- `ScrollModeV2Feature` — wheel modes via `02:30` plus the enabled-mode mask via `15:0b`.
- `highSpeedPollingRate` — `isHyperpollingWireless`, `smartDimming`.
- `orca5PlusCalibrationEngine` — surface calibration.
- `useGetDockEditionAPI` — Mouse Dock Pro detection.
- Button remap capabilities: disable, Hypershift, keyboard, mouse, macro, multimedia, sensitivity
  (DPI up/down/clutch/cycle), profile cycle, Perfect180.

## Verification status

Verified on hardware: the write path for the commands the app uses (read back from the mouse), the full
`02:0c` / `02:8c` button layout for all 14 buttons, and all three transports (USB, HyperSpeed dongle,
Bluetooth). See [TRANSPORTS.md](TRANSPORTS.md). Still open: the Perfect 180 per-game list format, and
`15:0b` returning a zero mask (`01 00`) when all scroll modes are enabled.

## Firmware & updater (Razer Customer Firmware Updater v1.03.00)

Analyzed statically and never executed. `BasiliskV4Pro_00E300E2_FirmwareUpdater_v1.03.00_r1.exe`,
sha256 `0370ad6a…4f45d8204c`, signed "Razer USA Ltd."

- **Package:** a small .NET stub plus a plain deflate ZIP overlay containing `WirelessCustomerFWUNew.exe`,
  `FWUpdaterDLL.dll`, `dfu1620-hid.dll`, `Ry_Online_Update_Dll_ouput_v1.0.1.dll`, `GComeUpdatingLibrary.dll`,
  `update/update_config.ini` and `load/flash_download.cfg`.
- **The bundled firmware is plaintext.** Decompiling the updater shows it reads the mouse and dongle images
  from embedded .NET resources as raw byte arrays, with no crypto. `encryption_en=1` and `.enc` in
  `update_config.ini` belong only to an unused online-update path.
- **Silicon:** both the mouse and the dongle run a **Nordic nRF54LM20A** (Cortex-M33) with Zephyr and the
  SoftDevice Controller. The Airoha `ab1623m_evk` / `dfu1620-hid.dll` / `0x08102000` references are generic
  scaffolding in Razer's multi-device updater framework and don't appear in the V4 Pro images.
- **Bootloader:** USB `1532:110E`. We never send DFU or bootloader commands.
- **Images:** `firmware/mouse_00E2_fw.bin` (434,860 B, complete v1.03.00 app) and
  `firmware/dongle_00E3_fw.bin` (130,840 B). Full analysis: [firmware/README.md](firmware/README.md) and
  [firmware/disasm/FINDINGS.md](firmware/disasm/FINDINGS.md). The command router in the image is the source of
  the complete class/id list in [DATASHEET.md](DATASHEET.md).
