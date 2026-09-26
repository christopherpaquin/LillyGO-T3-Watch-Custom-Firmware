# Hardware Validation

Per-peripheral status for watch `68ee8f48228c` (T-Watch S3 Plus). Status is
**PASS**, **FAIL**, or **NOT TESTED**.

## M0 baseline: LilyGo factory firmware

- Firmware: vendor factory example, built by `scripts/build-baseline.sh`
  (details in [`baseline-build.md`](baseline-build.md)), flashed 2026-09-23
  with `scripts/flash.sh`. Esptool verified all four regions.
- Factory backup: `backups/68ee8f48228c/factory-20260923T020006Z.bin`
  (sha256 `ecf305cd…570fbb`).

### Evidence from the serial boot log (2026-09-23)

```text
rst:0x15 (USB_UART_CHIP_RESET),boot:0x8 (SPI_FAST_FLASH_BOOT)
Listing directory: /            <- FFAT partition mounts, 8 sound files
I2C bus 1: 0x19 0x34 0x51 0x5A
I2C bus 2: 0x38
Start done. run main loop
```

| Address | Device | Bus |
|---|---|---|
| `0x19` | BMA423 accelerometer | 1 |
| `0x34` | AXP2101 PMIC | 1 |
| `0x51` | PCF8563 RTC | 1 |
| `0x5A` | DRV2605 haptic driver | 1 |
| `0x38` | FT6336U touch | 2 |

## Status

| Peripheral | Status | How verified / how to test |
|---|---|---|
| ESP32-S3, 8 MB PSRAM, 16 MB flash | PASS | `esptool flash-id` |
| Boot from flash | PASS | boot log above |
| FFAT filesystem | PASS | directory listing at boot |
| AXP2101 PMIC (I2C) | PASS | I2C scan `0x34` |
| PCF8563 RTC (I2C) | PASS | I2C scan `0x51` |
| BMA423 IMU (I2C) | PASS | I2C scan `0x19` |
| DRV2605 haptics (I2C) | PASS | I2C scan `0x5A` |
| FT6336U touch (I2C) | PASS | I2C scan `0x38` |
| Display | PASS | 2026-09-26: factory UI visible, readable; brightness setting visibly changes backlight |
| Touch input | PASS | 2026-09-26: swipes, tap-select, and corner/edge taps all respond |
| Side button (PMIC key) | PASS | 2026-09-26: short press turns screen off; next press brings it back on |
| Battery reading | PASS | 2026-09-26: factory power screen shows a sane percentage (87%) |
| Charging detection | NOT TESTED | factory UI exposes no live charge state (verified 2026-09-26, plugged and unplugged); however battery % rose 87% → 100% during the session, so the AXP2101 is almost certainly charging — will be confirmed definitively in M1a by reading the AXP2101 charge state directly via LilyGoLib |
| RTC keeps time | PASS | 2026-09-26: time/date set on factory UI, power-cycled, still correct on wake |
| IMU motion | FAIL | 2026-09-26: chip responds to I2C scan at `0x19` (standard BMA423 addr) but factory sensor screen shows a static red dot (no live values) and settings reports the accelerometer **offline** — chip-ID handshake is failing; investigate LilyGoLib BMA423 init (bus/address/chip-ID read) in the M1a IMU platform layer. Step count (M1b) and wake-on-raise (M1a) depend on this. |
| Haptics | PASS | 2026-09-26: vibration felt on power-on (factory build has no dedicated vibrate-test menu) |
| Speaker | PASS | 2026-09-26: factory audio screen plays the FFAT sound files; no volume control in factory UI (PCM amp gain is software-settable, so M1a audio layer can add it) |
| Microphone | PASS | 2026-09-26: factory mic screen level meter tracks speech (moves while speaking, flat when quiet) |
| Wi-Fi | PASS | 2026-09-26: factory wireless screen scans and lists nearby networks (factory keyboard too small for password entry without a stylus; M1b connects via `secrets.h` credentials so no on-device typing is needed) |
| BLE | NOT TESTED | factory build exposes no BLE screen/settings entry (verified 2026-09-26); will be validated in M1b by the NimBLE-Arduino platform wrapper (visible-from-phone check) |
| GPS | PASS | 2026-09-26: factory GPS screen shows module connected and a live satellite count (fix needs outdoors; full position validation comes with the P3 GPS feature) |
| LoRa radio | PASS | 2026-09-26: factory radio screen shows the full radio menu (not "Radio module not detected!"); firmware built with the vendor default `ARDUINO_LILYGO_LORA_SX1262` flag and RadioLib's `radio.begin()` performs a chip-ID check at init, so the fitted chip is an **SX1262** (open question #1 resolved; no radio re-pin needed). Radio defaults to disabled; no TX test performed. |
| IR transmitter | PASS | 2026-09-26: IR LED visibly activates when a test command is sent from the factory IR remote screen |
| Light sleep / wake | PASS | 2026-09-26: screen times out at the 60 s setting; big right-side button wakes; touch on the dark screen wakes |

## Notes

- **USB/boot quirk:** after an RTS reset over USB-Serial/JTAG the chip can
  land in download mode (`boot:0x0`, "waiting for download") because DTR is
  still asserted. `esptool --before no-reset --after watchdog-reset` always
  boots the app; `scripts/flash.sh` now does this after every upload.
- Opening the serial port can itself reset the chip. The port may come back
  as `/dev/ttyACM1` if something held `ttyACM0` open during re-enumeration.
- The LoRa build flag is the vendor default (`ARDUINO_LILYGO_LORA_SX1262`). **Confirmed correct 2026-09-26:** radio init passed its chip-ID check with that flag, so this watch has an SX1262.
