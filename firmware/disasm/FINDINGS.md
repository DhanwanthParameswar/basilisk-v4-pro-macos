# Firmware teardown — mouse_00E2_fw.bin (nRF54LM20A application, v1.03.00)

Static analysis with capstone (`fwlib.py`). Image never run; mouse never flashed.

## Load address & layout
- **Base = `0x22000`** (nRF54 MCUboot app slot), proven by string-pointer triangulation (235 pointers
  resolve to real strings) and a textbook Cortex-M33 reset routine.
- Image spans `0x22000`–`0x8c2ac` (434,860 B). Vector table at `0x22000` (SP `0x2001ae40`), 172 live IRQ
  vectors. Reset `0x62ddc`.

## Hardware (confirmed from code/strings)
- **Nordic nRF54LM20A**, Cortex-M33, Zephyr RTOS + **SoftDevice Controller** (`bt_hci_sdc`) for BLE.
- **Nordic nPM1300 PMIC** for battery charge + fuel gauge (`npm1300 fuel gauge derive init done`).
- USB High-Speed device (`usbhs@5a000`) — wired / 8 kHz path.
- On-device config persists via **Zephyr Settings + NVS** in internal flash (`FLASH_0`, "Loading settings…").
- GRTC timer; `nrfx` HAL. Razer board codename **"dragoon"**.

## Command transport (two front-ends, one protocol)
- **USB:** HID **feature report, 91 bytes** (report id + 90-byte Razer packet). `FeatureReportLen=91`.
- **BLE:** custom GATT service — **char1 = command in** (host writes; chunked writes reassembled in a
  256-byte RAM buffer at `0x20007714`), **char2 = response out** (notifications), char3 = read. Handler at
  `0x24bac`; completion wakes a worker (flag `0x20014dc4`).

## Command router (BLE path) — `0x56818` / table `0x56848`
Reads the command **class** byte, bounds-checks **`class ≤ 0x15`**, then a `tbb` jump table dispatches;
invalid/unimplemented class → **response byte[7] = 5 (NOT_SUPPORTED)**. This exactly matches the Razer
protocol-2.5 scheme and our reverse-engineered map (max class `0x15` = the Hapticore scroll class).

| class | BLE handler | | class | result |
|---|---|---|---|---|
| 0x00 device/system | `0x5412c` | | 0x02,0x04,0x06,0x07 | **not handled over BLE** (status 5) |
| 0x01 | `0x541d8` | | 0x09,0x0a,0x0c,0x0d,0x0e | status 5 |
| 0x03 | `0x547c4` | | 0x11–0x14 | status 5 |
| 0x05 profiles | `0x54450` | | | |
| 0x08 | `0x5498c` | | | |
| 0x0b sensor/calibration | `0x550e8` | | | |
| 0x0f Chroma lighting | `0x558b4` | | | |
| 0x10 | `0x56084` | | | |
| 0x15 Hapticore scroll | `0x56764` | | | |

### Key architectural finding
The **BLE** char1 router implements classes **{0,1,3,5,8,0b,0f,10,15}**. Our **live USB** sweep answered
**{0,2,4,5,6,7,0b,0f,10,15}**. The config-critical classes — **0x02 buttons, 0x04 DPI, 0x06 macros,
0x07 power** — are handled on the **USB feature-report path, not the BLE path**. So the two transports expose
**different command subsets**; a Mac app talking over USB gets the full config set (which is what we mapped
and verified). The separate USB dispatcher hasn't been located yet (next step if wanted).

Each class handler is itself a `tbb`/cmp switch on the command **id** with the same status-5 default (e.g.
class 0x00 handler `0x5412c` switches on ids 0x80/0x81/0x83…). Fully walking every per-class id table is the
remaining depth; it would reproduce, from the silicon, the command list we already have from the Synapse side.

## Tooling (reproducible)
- `fwlib.py` — loader/disassembler (base, string xrefs, func starts, disasm).
- `extract_cmds.py` — heuristic command-dispatcher finder.
Run from `firmware/disasm/`. Requires `pip install capstone`.
