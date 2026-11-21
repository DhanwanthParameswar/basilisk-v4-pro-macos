# Basilisk V4 Pro — command datasheet (reconstructed)

The commands the mouse firmware actually implements, by class and exact id. Built by cross-checking three sources; names/sizes come from decoded Razer Synapse call sites (the reliable source).

### How to read it
- Transport: USB HID **feature report, 91 bytes** (report id + 90-byte packet) or BLE char1. Packet: `[status, txid, 0,0,0, data_size, class, id, args…(≤80), crc, 0]`, crc = XOR of bytes 2..87.
- GET id = `0x80 | n`, SET id = `n`; listed as separate ids (they are distinct handlers).
- **evidence**: `FW` = present in the firmware dispatch tables (authoritative); `live` = the physical mouse answered that GET cleanly (trusted only for classes 0x00/0x02/0x07/0x10, which reject unknown ids — the other classes blanket-respond, so they rest on FW); `verified` = we captured/replayed its exact bytes on hardware.
- Blank name = firmware implements it but Synapse exposes no name for it on this device (undocumented).
- FW under-covers the cmp-chain handlers (classes 0x00, 0x0b), so those two are a lower bound.


## Class 0x00 — Device / system  (15 ids)

| id | dir | command | size | evidence |
|----|-----|---------|------|----------|
| `00:02` | SET | Set Serial Number | 22 | FW |
| `00:03` | SET |  |  | FW |
| `00:05` | SET | Set Device Polling Period | 1 | FW |
| `00:06` | SET | Set Edition Information | 3 | FW |
| `00:40` | SET | Set USB High Speed Polling Period | 2 | verified |
| `00:81` | GET | Get Firmware Version | 2 | live |
| `00:84` | GET | Get Device Mode | 2 | live |
| `00:86` | GET | Get Edition Information | 3 | live |
| `00:8d` | GET |  |  | live |
| `00:97` | GET |  |  | live |
| `00:a4` | GET |  |  | live |
| `00:b3` | GET |  |  | live |
| `00:bb` | GET | Get Device On Dock Charging Status | 1 | live |
| `00:c0` | GET | Get USB High Speed Polling Period | 2 | live+verified |
| `00:db` | GET | Get Tournament Mode | 1 | FW |

## Class 0x02 — Buttons & scroll wheel  (25 ids)

| id | dir | command | size | evidence |
|----|-----|---------|------|----------|
| `02:00` | SET |  |  | FW |
| `02:09` | SET |  |  | FW |
| `02:0c` | SET | Set Single Button Assignment | 80 | FW+verified |
| `02:16` | SET | Set Scroll Virtual Acceleration State | 2 | verified |
| `02:17` | SET | Set Scroll Mode Auto Switch State | 80 | verified |
| `02:22` | SET | Set Scroll Virtual Acceleration Level | 2 | verified |
| `02:23` | SET | Set Scroll Wheel Smart Reel Mode Threshold | 2 | verified |
| `02:30` | SET | Set Scroll Tactile/Free Spin/Micro Tactile Mode | 2 | verified |
| `02:34` | SET | Set Remove Keymap | 2 | FW |
| `02:82` | GET |  |  | FW |
| `02:83` | GET |  |  | FW |
| `02:84` | GET |  |  | FW |
| `02:86` | GET |  |  | FW |
| `02:87` | GET |  |  | FW |
| `02:8c` | GET |  |  | FW |
| `02:8e` | GET | Get Button Assignment List | 80 | FW |
| `02:96` | GET |  |  | FW+live |
| `02:97` | GET |  |  | FW+live |
| `02:98` | GET |  |  | FW+live |
| `02:a2` | GET |  |  | FW+live |
| `02:a3` | GET |  |  | FW+live |
| `02:b0` | GET | Get Scroll Tactile/Free Spin/Micro Tactile Mode | 2 | FW+live |
| `02:b3` | GET |  |  | FW+live |
| `02:b4` | GET |  |  | FW+live |
| `02:b6` | GET | Get Active Keymap | 2 | FW |

## Class 0x04 — DPI / sensitivity  (21 ids)

| id | dir | command | size | evidence |
|----|-----|---------|------|----------|
| `04:00` | SET |  |  | FW |
| `04:02` | SET |  |  | FW |
| `04:03` | SET |  |  | FW |
| `04:04` | SET |  |  | FW |
| `04:05` | SET | Set Profile Active DPI Setting | 7 | FW+verified |
| `04:06` | SET | Set Profile DPI Class Data | 80 | FW+verified |
| `04:13` | SET |  |  | FW |
| `04:14` | SET |  |  | FW |
| `04:15` | SET |  |  | FW |
| `04:16` | SET |  |  | FW |
| `04:7f` | SET |  |  | FW |
| `04:80` | GET |  |  | FW |
| `04:81` | GET |  |  | FW |
| `04:82` | GET |  |  | FW |
| `04:83` | GET |  |  | FW |
| `04:84` | GET |  |  | FW |
| `04:85` | GET | sendCommand | 7 | FW+verified |
| `04:86` | GET | Get Profile DPI Class Data | 80 | FW+verified |
| `04:93` | GET |  |  | FW |
| `04:95` | GET |  |  | FW |
| `04:96` | GET |  |  | FW |

## Class 0x05 — Onboard profiles  (9 ids)

| id | dir | command | size | evidence |
|----|-----|---------|------|----------|
| `05:02` | SET | Create New Profile | 1 | verified |
| `05:03` | SET | Set Delete Profile | 1 | verified |
| `05:08` | SET | Set Profile Name With Offset | 80 | FW+verified |
| `05:80` | GET |  |  | FW |
| `05:81` | GET |  |  | FW |
| `05:84` | GET |  |  | FW |
| `05:88` | GET |  |  | FW |
| `05:89` | GET |  |  | FW |
| `05:8a` | GET |  |  | FW |

## Class 0x06 — Macros  (14 ids)

| id | dir | command | size | evidence |
|----|-----|---------|------|----------|
| `06:03` | SET | Delete Macro | 2 | verified |
| `06:08` | SET | Allocate Macro Data Size | 6 | verified |
| `06:09` | SET | Set Macro Memory Data | 80 | verified |
| `06:0c` | SET | Set Macro Name With Offset | 80 | FW+verified |
| `06:80` | GET |  |  | FW |
| `06:82` | GET |  |  | FW |
| `06:87` | GET |  |  | FW |
| `06:88` | GET |  |  | FW |
| `06:89` | GET | Get Macro Memory Data | 80 | FW |
| `06:8a` | GET | Get Macro Memory Management | 6 | FW |
| `06:8b` | GET | Ro | 80 | FW |
| `06:8c` | GET | Get Macro Name With Offset | 80 | FW |
| `06:8d` | GET |  |  | FW |
| `06:8e` | GET |  |  | FW |

## Class 0x07 — Power / battery  (12 ids)

| id | dir | command | size | evidence |
|----|-----|---------|------|----------|
| `07:01` | SET | Set Battery Critical Level | 1 | verified |
| `07:03` | SET | Set Time to Sleep Mode on Battery Mode | 2 | verified |
| `07:13` | SET | Set Smart illumination Control | 3 | FW+verified |
| `07:80` | GET | Get Battery Level | 2 | FW+live |
| `07:81` | GET | Get Battery Critical Level | 1 | FW+live |
| `07:82` | GET | Get LED Max Brightness on Battery Mode | 1 | FW |
| `07:83` | GET | Get Time to Sleep Mode on Battery Mode | 2 | FW |
| `07:84` | GET | Get Device Charging Status | 2 | FW |
| `07:85` | GET |  |  | FW |
| `07:8d` | GET |  |  | FW+live |
| `07:92` | GET |  |  | FW |
| `07:93` | GET | Get Smart illumination Control | 3 | FW+live |

## Class 0x0b — Sensor / calibration / dynamic sensitivity  (27 ids)

| id | dir | command | size | evidence |
|----|-----|---------|------|----------|
| `0b:03` | SET | Set Proximity Sensor State | 3 | FW+verified |
| `0b:04` | SET | Set Proximity Sensor Hardware | 6 | FW |
| `0b:05` | SET | Set Proximity Sensor Configuration | 10 | verified |
| `0b:06` | SET |  |  | FW |
| `0b:07` | SET | Set Proximity Sensor Accuracy | 3 | FW |
| `0b:0b` | SET |  |  | verified |
| `0b:10` | SET | Set Proximity Sensor Acceleration State | 2 | verified |
| `0b:11` | SET | Set Proximity Sensor Acceleration Mode | 2 | verified |
| `0b:13` | SET | Set Proximity Sensor Acceleration curve data | 37 | verified |
| `0b:30` | SET |  |  | FW |
| `0b:31` | SET |  |  | FW |
| `0b:33` | SET |  |  | FW |
| `0b:34` | SET |  |  | FW |
| `0b:35` | SET |  |  | FW |
| `0b:36` | SET |  |  | FW |
| `0b:37` | SET |  |  | FW |
| `0b:38` | SET |  |  | FW |
| `0b:39` | SET |  |  | FW |
| `0b:3a` | SET |  |  | FW |
| `0b:3b` | SET |  |  | FW |
| `0b:3c` | SET |  |  | FW |
| `0b:41` | SET |  |  | FW |
| `0b:49` | SET |  |  | FW |
| `0b:52` | SET |  |  | FW |
| `0b:95` | GET |  |  | FW |
| `0b:d6` | GET |  |  | FW |
| `0b:fd` | GET |  |  | FW |

## Class 0x0f — Chroma lighting  (22 ids)

| id | dir | command | size | evidence |
|----|-----|---------|------|----------|
| `0f:00` | SET |  |  | FW |
| `0f:02` | SET | Set Chroma Effect | 80 | FW+verified |
| `0f:03` | SET | Set Chroma Frame | 80 | FW |
| `0f:04` | SET | Set Chroma Brightness | 3 | FW+verified |
| `0f:05` | SET | Set Chroma Calibration | 5 | FW |
| `0f:0a` | SET |  |  | FW |
| `0f:10` | SET | Set Force Chroma Ctrl | 1 | FW |
| `0f:11` | SET |  |  | FW |
| `0f:7f` | SET |  |  | FW |
| `0f:81` | GET | Get Chroma Effect ID List | 80 | FW |
| `0f:82` | GET | Get Chroma Effect | 80 | FW+verified |
| `0f:83` | GET |  |  | FW |
| `0f:86` | GET | Get Chroma Fn Overlay Control | 2 | FW |
| `0f:87` | GET |  |  | FW |
| `0f:8a` | GET |  |  | FW |
| `0f:8b` | GET |  |  | FW |
| `0f:8e` | GET |  |  | FW |
| `0f:91` | GET |  |  | FW |
| `0f:96` | GET |  |  | FW |
| `0f:9d` | GET |  |  | FW |
| `0f:f1` | GET |  |  | FW |
| `0f:fe` | GET |  |  | FW |

## Class 0x10 — Class 0x10 (undocumented)  (14 ids)

| id | dir | command | size | evidence |
|----|-----|---------|------|----------|
| `10:00` | SET |  |  | FW |
| `10:01` | SET |  |  | FW |
| `10:02` | SET |  |  | FW |
| `10:03` | SET |  |  | FW |
| `10:04` | SET |  |  | FW |
| `10:05` | SET |  |  | FW |
| `10:06` | SET |  |  | FW |
| `10:07` | SET |  |  | FW |
| `10:08` | SET |  |  | FW |
| `10:09` | SET |  |  | FW |
| `10:0b` | SET |  |  | FW |
| `10:81` | GET |  |  | FW |
| `10:83` | GET |  |  | live |
| `10:84` | GET |  |  | FW |

## Class 0x15 — Hapticore scroll wheel  (10 ids)

| id | dir | command | size | evidence |
|----|-----|---------|------|----------|
| `15:0b` | SET | Set LK Scroll Wheel Mode Selected Information | 2 | FW |
| `15:31` | SET |  |  | FW |
| `15:32` | SET |  |  | FW |
| `15:33` | SET |  |  | FW |
| `15:39` | SET |  |  | FW |
| `15:4a` | SET |  |  | FW |
| `15:55` | SET |  |  | FW |
| `15:87` | GET | Get Hapticore Scroll Stage Information | 9 | FW |
| `15:b5` | GET |  |  | FW |
| `15:fe` | GET |  |  | FW |
