# T-Watch S3 Plus Homelab Firmware

![License](https://img.shields.io/badge/license-Apache--2.0-blue)
![Board](https://img.shields.io/badge/board-LILYGO%20T--Watch%20S3%20Plus-orange)
![Tested on](https://img.shields.io/badge/tested%20on-Ubuntu%2024.04-E95420)
![Status](https://img.shields.io/badge/status-M0%20baseline-yellow)

Custom firmware for the **LILYGO T-Watch S3 Plus**: a wearable watch first,
then a glanceable homelab status panel and remote-agent terminal. Built on
[LilyGoLib](https://github.com/Xinyuan-LilyGO/LilyGoLib). See
[`plan.md`](plan.md) for the full plan and milestones.

## 📋 Contents

- [🎯 Overview](#-overview)
- [📦 Requirements](#-requirements)
- [🏗️ Architecture](#️-architecture)
- [🚀 Installation](#-installation)
- [🗑️ Uninstall](#️-uninstall)
- [🔧 Usage](#-usage)
- [⚙️ Configuration](#️-configuration)
- [🩺 Troubleshooting](#-troubleshooting)
- [🔒 Security notes](#-security-notes)
- [📄 License](#-license)

---

## 🎯 Overview

| Milestone | What you get | Status |
|---|---|---|
| M0 | Flash backup/restore safety net, vendor baseline, hardware validation | 🚧 in progress |
| M1a | Offline watch: face, battery, sleep/wake, launcher, diagnostics | ❌ |
| M1b | Wi-Fi, NTP, steps, timer | ❌ |
| M2 | Homelab status screens | ❌ |
| M3+ | Alerts, agents, voice, OTA | ❌ |

---

## 📦 Requirements

| Tool | Why | Installed by |
|---|---|---|
| Linux host, user in `dialout` group | serial access to the watch | you |
| `pipx`, `git`, `bats`, `shellcheck` | tooling and tests | you (`apt`) |
| PlatformIO, esptool, pre-commit | build, flash, hooks | `install.sh` |

---

## 🏗️ Architecture

```text
┌──────────────────────────────────────────────┐
│ UI (LVGL 9): screens, widgets, navigation    │  UI task only
├──────────────────────────────────────────────┤
│ Services: time, config, storage, telemetry   │
│ Network worker task ◄── event bus ──►        │
├──────────────────────────────────────────────┤
│ Platform: display, touch, power, rtc, imu …  │  wraps LilyGoLib
├──────────────────────────────────────────────┤
│ LilyGoLib 0.2.x                              │
├──────────────────────────────────────────────┤
│ arduino-esp32 / ESP-IDF on ESP32-S3          │
└──────────────────────────────────────────────┘
```

Details in [`plan.md`](plan.md#core-principles).

---

## 🚀 Installation

- [ ] Install system tools: `sudo apt install pipx git bats shellcheck`
- [ ] Run `./install.sh` (safe to re-run)
- [ ] Plug in the watch and run `./healthcheck.sh`
- [ ] **Once per watch, before any flashing:** `scripts/backup-flash.sh --label factory`

---

## 🗑️ Uninstall

```bash
./uninstall.sh                 # hooks, build output, vendor checkout
./uninstall.sh --purge-tools   # also removes PlatformIO/esptool/pre-commit
```

⚠️ `backups/` is never deleted by the uninstaller. It's the only way back to
factory firmware.

---

## 🔧 Usage

| Task | Command |
|---|---|
| Check the watch is reachable and backed up | `./healthcheck.sh` |
| Full-flash backup (read twice, verified) | `scripts/backup-flash.sh [--label NAME]` |
| Build the vendor factory firmware (M0) | `scripts/build-baseline.sh` |
| Flash a PlatformIO env (needs a verified backup) | `scripts/flash.sh --project DIR --env ENV` |
| Restore a backup (typed confirmation, read-back check) | `scripts/restore-flash.sh backups/<mac>/<file>.bin` |
| Recover a stale USB link | `scripts/usb-reset.sh` |
| Run script tests | `bats tests/scripts` |

---

## ⚙️ Configuration

| Variable | Default | Purpose |
|---|---|---|
| `WATCH_PORT` | `/dev/ttyACM0` | serial port |
| `ESPTOOL_OPTS` | *(empty)* | extra esptool options; use `--before no-reset --after no-reset` while the watch is in download mode |
| `BACKUP_ROOT` | `./backups` | where flash images are stored |

Firmware secrets (Wi-Fi, backend token) will live in `include/secrets.h`,
which is gitignored. This starts in M1b.

---

## 🩺 Troubleshooting

- [ ] **`Errno 71 Protocol error` / `can't set config #1, error -71`**: the
  USB link went stale, usually because the firmware put USB to sleep. Run
  `scripts/usb-reset.sh`. If that fails, use download mode.
- [ ] **Download mode:** hold **BOOT**, tap **RST**, release BOOT (both on the
  case edge). The ROM bootloader always answers. Press RST to leave it.
- [ ] **Watch won't boot after a flash:** enter download mode, then
  `scripts/restore-flash.sh backups/<mac>/factory-*.bin`.
- [ ] **`flash.sh` refuses to run:** there's no verified backup for this
  watch. Run `scripts/backup-flash.sh`.

---

## 🔒 Security notes

- ✅ Flash backups are `0700`/`0600` and gitignored. Once our firmware has run
  on a watch, its backups contain Wi-Fi credentials and the device token.
- ✅ `flash.sh`/`restore-flash.sh` refuse to write without a verified backup
  of the connected watch (MAC, size and SHA-256 checked).
- ✅ pre-commit runs secret detection on every commit.
- ⚠️ The watch has no flash encryption: treat a lost watch's token as
  compromised and revoke it. See [`plan.md`](plan.md#security).

---

## 📄 License

Apache-2.0, see [`LICENSE`](LICENSE). LilyGoLib is MIT-licensed and is pulled
in as a dependency, not vendored.
