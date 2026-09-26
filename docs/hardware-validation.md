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
| Display | NOT TESTED | factory UI visible, readable, backlight changes with brightness |
| Touch input | NOT TESTED | tap and swipe through factory menus, corners included |
| Side button (PMIC key) | NOT TESTED | short press turns screen off/on |
| Battery reading | NOT TESTED | factory power screen shows a sane voltage/percentage |
| Charging detection | NOT TESTED | power screen shows charging when USB is plugged in, not charging when unplugged |
| RTC keeps time | NOT TESTED | set the time, power-cycle, time still correct |
| IMU motion | NOT TESTED | factory sensor screen values change when the watch moves |
| Haptics | NOT TESTED | vibration is felt (factory vibrate test / tap feedback) |
| Speaker | NOT TESTED | factory audio/music screen plays a sound |
| Microphone | NOT TESTED | factory microphone screen shows level changes when speaking |
| Wi-Fi | NOT TESTED | factory wireless screen scans and lists networks |
| BLE | NOT TESTED | factory BLE screen advertises / is visible from a phone |
| GPS | NOT TESTED | factory GPS screen detects the module (fix needs outdoors) |
| LoRa radio | NOT TESTED | factory radio screen initializes; **record the chip model it shows** |
| IR transmitter | NOT TESTED | factory IR remote screen sends; check with a phone camera |
| Light sleep / wake | NOT TESTED | screen times out and wakes on button and touch |

## Notes

- **USB/boot quirk:** after an RTS reset over USB-Serial/JTAG the chip can
  land in download mode (`boot:0x0`, "waiting for download") because DTR is
  still asserted. `esptool --before no-reset --after watchdog-reset` always
  boots the app; `scripts/flash.sh` now does this after every upload.
- Opening the serial port can itself reset the chip. The port may come back
  as `/dev/ttyACM1` if something held `ttyACM0` open during re-enumeration.
- The LoRa build flag is the vendor default (`ARDUINO_LILYGO_LORA_SX1262`).
  If this watch has a different radio, the radio screen will fail to init.
  That shows the fitted chip isn't an SX1262, not that the hardware is broken.
