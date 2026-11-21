# Basilisk — native macOS app for the Razer Basilisk V4 Pro

SwiftUI app for macOS 27 (Liquid Glass) that configures the mouse directly over the protocol
documented in [../PROTOCOL.md](../PROTOCOL.md) and [../TRANSPORTS.md](../TRANSPORTS.md). It has no
helper daemons and no kernel extensions, and never asks for Input Monitoring.

## Build and run

```bash
./build_app.sh
```

```bash
open build/Basilisk.app
```

`build_app.sh` runs `swift build -c release`, assembles `build/Basilisk.app`, renders the icon from the
vector artwork (`Basilisk --render-icon <dir>` → `iconutil`), writes Info.plist (with the Bluetooth usage
string) and ad-hoc signs it. You can copy the app to /Applications.

## What it does

| Pane | Controls | Commands |
|---|---|---|
| Overview | Live artwork with animated lighting preview; DPI, polling, battery, scroll mode; quick stage buttons | reads only |
| Performance | Up to 5 DPI stages (log slider and field, 100–50,000), active stage, polling 125 Hz–8 kHz, lift-off distance | `04:06` `00:40` `0b:0b` |
| Buttons | Remap 13 buttons (mouse, sensitivity, clutch, profile, scroll mode, Hypershift, keyboard shortcut, disable), factory reset. Left click is locked | `02:8c` / `02:0c` |
| Scroll Wheel | Tactile / Free-Spin / Precision, which modes the button cycles, acceleration and Smart-Reel with levels | `02:30` `15:0b` `02:16/22` `02:17/23` |
| Lighting | Click a zone on the mouse or edit all zones; Off/Static/Breathing/Spectrum/Wave/Reactive, colour, wave direction, brightness, idle dimming | `0f:02` `0f:04` `07:13` |
| Power | Battery and charging, sleep timeout, low-power threshold | `07:80/84` `07:03` `07:01` |
| Menu bar | Battery, stage buttons, polling, scroll mode | — |

All settings are saved **on the mouse**, so they keep working without the app.

## Architecture

```
Sources/Basilisk/
  App/BasiliskApp.swift     Window + MenuBarExtra + Settings, shared DeviceManager, icon renderer
  Core/Packet.swift         90-byte Razer report encode/decode (CRC, status)
  Core/Transport.swift      RazerTransport protocol (usb / dongle / bluetooth)
  Core/HIDTransport.swift   IOHIDDevice feature reports; dongle = async poll + resend on status 4
  Core/BLETransport.swift   CoreBluetooth vendor service (8-byte header framing), battery via 2A19
  Core/V4Pro.swift          Typed command builders/parsers for this mouse
  Core/Model.swift          DPI stages, polling, scroll modes, lighting, buttons/actions, key names
  Core/DeviceManager.swift  @Observable state, discovery, link preference, optimistic writes
  Art/                      Synapse artwork converted to native SwiftUI paths (tools/svg2swift.py)
  Views/                    Panes, components, menu bar, settings
```

How it stays efficient:
- **Discovery is event-driven.** IOHIDManager hot-plug callbacks match only the vendor control
  interface (usage page 0x0C, 90-byte feature report). There's no USB polling, and it never opens
  the keyboard interface, which is why no Input Monitoring prompt appears.
- **Link preference:** wired > HyperSpeed dongle > Bluetooth. A dongle is only used once the mouse
  answers through it. Bluetooth is a fallback after 1.5 s with no USB link.
- **Full read once per connect.** After that only battery, charging and the active stage are
  refreshed: every 4 s while the window is visible, every 60 s otherwise (timer tolerance 25%).
- **Writes are optimistic.** The UI updates at once and reverts with an alert if the mouse rejects the
  write. Sliders and text fields only send when you let go or press Return.
- **Drawing is cheap.** The artwork is pre-parsed Paths in a single Canvas. The lighting animation runs
  only for moving effects, is capped at 20 fps, and pauses when hidden.
- **VM detection.** If a Parallels/VMware VM has claimed the USB device, the app says so instead of
  searching forever.

## Limits

- Over **Bluetooth** the firmware only accepts classes 00, 05 and 10. You get battery, firmware and
  profiles; everything else is shown read-only, with a note to use the cable or dongle.
- Not exposed (yet): macros, onboard profile management, Hypershift-layer remaps, Perfect 180.
  The protocol for all of these is documented in PROTOCOL.md.

## Verified on hardware (wired, 2026-11-21, firmware 1.02)

- Reads: firmware, serial, DPI stages, polling, smart tracking, scroll mode, acceleration,
  Smart-Reel, brightness, per-zone effects (`0f:82`), smart dimming (`07:93`), sleep (`07:83`),
  low power (`07:81`), all 14 button assignments (`02:8c`).
- Writes, read back from the mouse: active DPI stage, lighting effect on all zones (Static ↔ Spectrum).
- `15:8b` (enabled scroll modes) returns `01 00` with all modes enabled; the app treats a zero mask
  as "all enabled".

The mouse artwork is Razer's, extracted from Synapse (see the disclaimer in the top-level README).
