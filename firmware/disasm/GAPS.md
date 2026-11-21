# What we know vs. don't — firmware (mouse_00E2_fw.bin)

## Solidly mapped
- **Silicon & stack:** nRF54LM20A, Cortex-M33, Zephyr + SoftDevice Controller, nPM1300 PMIC, USB-HS, NVS settings.
- **Transport & packet format** (USB feature report + BLE char1/char2), image base, vector table.
- **Command router architecture:** main USB router `0x54032`, BLE router `0x56844`, the 10 implemented classes,
  and the per-class id tables (9 of the 111 jump tables are command tables; the other 102 are ordinary code —
  so there is **no hidden extra command surface**).
- **The command list:** 169 command ids → `DATASHEET.md`.
- **~40 commands verified byte-for-byte** (captured or replayed) — these have exact argument layouts in `PROTOCOL.md`.

## Still unknown (firmware)
1. **Argument / response byte layouts for ~130 of the 169 commands.** We know the id and total size, not what each
   arg byte means. (The 40 verified ones do have this.) This is the main gap if we want a *complete* spec.
2. **What the undocumented commands do** — the blank-name rows in the datasheet (all of class 0x10, several class
   0x04/0x0b/0x15 ids). Firmware implements them; Synapse never names them. Semantics unknown.
3. **Classes 0x00 and 0x0b** use if-else dispatch, not jump tables, so their firmware-side id lists are a lower
   bound (backfilled from the live device).
4. **A few datasheet ids tagged FW-only** may be analyzer artifacts (e.g. `04:7f`) — unverified.
5. **The actual feature implementations** (not the command protocol, and not needed to build an app):
   sensor/motion driver (PixArt, over SPI), DPI pipeline, the HyperSpeed 2.4 GHz radio protocol, BLE pairing/
   bonding, the on-device profile/NVS storage format, Hapticore haptic-scroll control, nPM1300 power management.
6. **The dongle firmware** (`dongle_00E3_fw.bin`) — extracted but barely analyzed; it has its own command handling
   and the 2.4 GHz link half.

## Reality check
The mouse app only needs #1–#3 for the commands it will actually send (DPI, buttons, lighting, scroll, power,
profiles, macros) — and those are the verified ones. #5 is the internal implementation of a full RTOS mouse;
"fully deconstructing" it is an open-ended effort and isn't required to configure the device.
