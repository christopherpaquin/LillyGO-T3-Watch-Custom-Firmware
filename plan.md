# T-Watch S3 Plus Homelab Firmware — Plan

## Project Goal

Build custom firmware for the **LILYGO T-Watch S3 Plus** that is useful to wear
every day, then grow it into a glanceable homelab control panel and
remote-agent terminal.

- **LilyGoLib** is the hardware layer. We do not rewrite what it provides.
- **NanoClaw Watch** is *reference material*, not a fork (see
  [Decisions](#decisions)).
- The watch is a **thin client**. Complex logic lives on homelab systems.

Priority order: **a working watch first**, homelab visibility second, agent
control and voice after that.

---

## Verified Facts (2026-09-22)

### Device on the bench

Read with `esptool flash-id` over `/dev/ttyACM0`:

| Item | Value |
|---|---|
| SoC | ESP32-S3 (QFN56) rev v0.2, dual core, 240 MHz |
| PSRAM | 8 MB embedded (AP_3v3) |
| Flash | 16 MB, Winbond (`ef`/`4018`), quad, 3.3 V |
| USB | native USB-Serial/JTAG (`303a:1001`) |
| MAC | `68:ee:8f:48:22:8c` |
| Current firmware | LilyGo factory firmware (I2C scan + `Start done. run main loop`) |
| LoRa radio variant | **unknown — confirm in M0** (SX1262 / SX1280 / CC1101 / LR1121 / SI4432 all exist) |

#### USB quirk

The host has seen the USB-CDC link go stale (`Errno 71 Protocol error`,
`can't set config #1, error -71`). Recovery, in order:

1. Software re-plug: unbind/bind the USB device in sysfs
   (`scripts/usb-reset.sh`, to be written).
2. Wake the watch (light sleep suspends USB-Serial/JTAG), then physically
   re-plug directly into the PC (no hub).
3. Download mode: hold **BOOT**, tap **RST**, release BOOT (both on the case
   edge). ROM bootloader always answers regardless of installed firmware.

Early boot log lines are lost on reset because USB-CDC re-enumerates. Firmware
must delay briefly or buffer its startup report so it can be captured.

### Toolchain (proven on this watch, 2026-09-23)

- **PlatformIO + Arduino framework** on the **pioarduino** platform
  release **`55.03.39`** (arduino-esp32 **3.3.9**, ESP-IDF 5.5.4). LilyGoLib
  0.2.1 + LilyGo factory example built and ran on the watch with it (see
  `docs/baseline-build.md`).
- LilyGo's own `LilyGoLib-PlatformIO` config is **not** buildable as shipped
  for 0.2.x: its `espressif32@6.12.0` (Arduino 2.0.17 / IDF 4.4) lacks the
  IDF 5 LCD APIs LilyGoLib uses, and its `ESP32 BLE Arduino` registry
  dependency breaks on Arduino 3.x (the core has its own BLE library). Add
  `lib_ignore = ESP32 BLE Arduino`.
- The vendor project also has an **SDL desktop emulator env**
  (`emulator_twatchs3`, 240×240). Use it for UI work in M1a so most UI
  changes don't need a flash.
- After an upload, reset with `esptool --after watchdog-reset`; an RTS reset
  can leave the chip in download mode (see `docs/hardware-validation.md`).
- Custom board JSON (variant `lilygo_twatch_s3`, 16 MB flash, `qio_opi`,
  `-DBOARD_HAS_PSRAM`) because pioarduino doesn't ship one.
- Capability defines must be set **globally** in `build_flags`
  (`-DUSING_INPUT_DEV_TOUCHPAD -DUSING_PDM_MICROPHONE -DUSING_PCM_AMPLIFIER
  -DUSING_PMU_MANAGE -DUSING_IR_REMOTE`), otherwise library files compile
  without them (upstream saw LVGL come up with **no touch input**).
- **LilyGoLib 0.2.1** (released 2026-09-19). It pulls LVGL 9 and
  third-party deps (LilyGoLib-ThirdParty).
- There is no `sdkconfig.defaults`; ESP-IDF options come from the Arduino core.

#### Pinning policy

- Platform: the exact pioarduino release zip URL. Arduino core version is
  whatever that release bundles; record it.
- Libraries: exact versions (`@0.2.1`, never `^`/`~`) or git URLs at a tag or
  commit SHA. No floating branches.
- After the first successful build, `scripts/deps-manifest.sh` writes
  `deps.lock.json`: a normalized, sorted list of `{name, version, source}` for
  the platform, Arduino core, toolchain, and every library including
  transitive ones. No host paths. `scripts/check.sh` regenerates it and fails
  on any diff.
- Dependency updates are their own change: bump, rebuild, re-run the hardware
  smoke test, commit the new `deps.lock.json`.

### Partition table (required by LilyGoLib)

LilyGoLib requires a FAT partition labeled `ffat`, otherwise `setupMSC()` loops
forever and `watch.begin()` never returns. Use the layout **read from this
watch's factory image** (2026-09-22 backup, offset 0x8000). It differs from
NanoClaw's copy by keeping a coredump partition, which we want for crash
debugging:

```text
nvs      data nvs      0x9000   0x5000
otadata  data ota      0xe000   0x2000
app0     app  ota_0    0x10000  0x400000
app1     app  ota_1    0x410000 0x400000
ffat     data fat      0x810000 0x7E0000
coredump data coredump 0xFF0000 0x10000
```

Two 4 MB OTA slots are already present, so the future OTA milestone needs no
repartition.

### Hardware notes that affect design

- **Side button** is the AXP2101 PMIC power key, not a GPIO. Short press is
  readable as an event; a long press can hard power-off the PMIC. Never map a
  long hold to an app action.
- **IR transmitter** is present (`USING_IR_REMOTE`). In scope as P3.
- **GPS** (S3 Plus only): must be driven through LilyGoLib (`instance.gps`) and
  power-gated through the PMIC. Upstream bypasses LilyGoLib here; don't copy
  that.

---

## Decisions

| # | Decision | Why |
|---|---|---|
| D1 | **New codebase on LilyGoLib; NanoClaw is read-only reference.** | Upstream has no reusable framework (107 KB `ui.cpp`, 44 KB `main.cpp`), makes blocking HTTP calls from the UI loop, has a committed auth token, plain-HTTP unsigned OTA, and **no LICENSE file** (README claims MIT). |
| D2 | **LilyGoLib 0.2.1**, exact pin. | Current release; contains S3 Plus docs/schematic. Upstream's `^0.1.0` pin locks to 0.1.x. |
| D3 | **Don't copy NanoClaw code** until the author adds a LICENSE file. Build settings/facts learned from it (above) are fine to reuse. | Licensing. |
| D4 | **Async network from day one**: one network worker task; LVGL is touched only from the UI task. | The hardest thing to retrofit; upstream's main defect. |
| D5 | **No OTA until M6**, and only after the M6 OTA design is approved. | Upstream OTA is unauthenticated HTTP. |
| D6 | **Wi-Fi and endpoints via gitignored `secrets.h`** for now; provisioning UI later. | Fastest path to a working watch without committing secrets. |

---

## Core Principles

1. **Preserve known-good hardware support.** Custom code sits *above*
   LilyGoLib. Bypassing it requires a documented reason.
2. **Layered architecture.** UI consumes services; services consume the
   platform layer; only the platform layer includes LilyGoLib headers.
3. **Local-first.** The watch is fully useful with no network. Remote features
   fail gracefully and never block the UI.
4. **Battery life is a feature.** Nothing polls continuously without a reason
   and a measured cost.
5. **Agent-friendly codebase.** Small modules, explicit interfaces, pinned
   versions, native-testable logic, one concern per change.

```text
+--------------------------------------------------+
|  UI (LVGL 9) — screens, widgets, navigation      |   UI task only
+--------------------------------------------------+
|  Services — time, config, storage, telemetry,    |
|  alerts, agent, audio                            |
|  Network worker task  <-- queue / event bus -->  |
+--------------------------------------------------+
|  Platform — display, touch, power, battery, rtc, |
|  imu, haptics, audio, wifi, ble, gps, lora, ir   |
+--------------------------------------------------+
|  LilyGoLib 0.2.1  +  LVGL helper                 |
+--------------------------------------------------+
|  arduino-esp32 3.3.x (ESP-IDF 5.x) / ESP32-S3    |
+--------------------------------------------------+
```

### Threading rule

- LVGL calls happen **only** on the UI task.
- Network I/O happens **only** on the network worker task.
- They communicate through a FreeRTOS queue / small event bus. Results are
  posted as events (`TelemetryUpdated`, `NetworkStateChanged`, …).
- No `delay()`, blocking HTTP, or `lv_refr_now()` loops in UI code.

#### Event bus contract

- Bounded FreeRTOS queues with fixed-size event structs (type, id, small
  scalar payload). No heap pointers cross tasks.
- Large data (host lists, alerts) lives in the state store, which is written by
  the worker under a mutex and read by the UI by snapshot. Events only say
  "X changed, generation N".
- Queue full: coalesce state-change events (latest wins); never block the
  producer. Count drops and show them in Diagnostics.
- Every network request has a timeout (default 5 s connect, 10 s total) and
  exponential backoff (max 5 min). Results from a request older than the
  current generation are discarded.
- Before light sleep the worker finishes or aborts its request and parks; on
  wake it resumes. It never runs during deep sleep.
- Response bodies are size-capped per endpoint (default 16 KB; host list and
  alerts 64 KB). The worker reads into a fixed PSRAM buffer: a
  `Content-Length` over the cap is rejected before reading, and chunked or
  unknown-length bodies are cut off at the cap and rejected. ArduinoJson parses
  with a fixed-capacity document; parse overflow means the response is rejected
  and the cached state kept.

---

## Repository Structure

```text
.
├── plan.md                  this file
├── AGENTS.md                rules for coding agents (from "Agent Rules" below)
├── README.md                build / flash / recover instructions
├── WORKLOG.md               decision log
├── platformio.ini           envs: twatch-s3-plus (prod), twatch-s3-plus-mock, native
├── deps.lock.json           normalized resolved dependency manifest
├── partitions.csv           ffat layout above
├── boards/twatch-s3-plus.json
├── include/
│   ├── app_config.h         defaults, intervals, feature flags
│   ├── secrets.h.example    committed template
│   └── secrets.h            gitignored
├── lib/                     pure C++ logic, no Arduino/LilyGoLib — native-testable
│   ├── model/               host, alert, agent-session structs
│   ├── parse/               JSON -> model (ArduinoJson)
│   ├── safety/              command risk classification
│   └── util/                ring buffers, formatting, time helpers
├── src/
│   ├── main.cpp             setup/loop only; wires layers together
│   ├── core/                event_bus, tasks, logging, state_store
│   ├── platform/            one file per peripheral, wraps LilyGoLib
│   ├── services/            network, time, config, storage, telemetry, ...
│   └── ui/                  ui_manager, theme, navigation, screens/, widgets/
├── test/
│   ├── native/              runs on host via `pio test -e native`
│   └── hardware/            smoke-test checklists / on-device test sketches
├── scripts/
│   ├── build.sh  flash.sh  monitor.sh  check.sh
│   ├── backup-flash.sh      full 16 MB read to backups/ (gitignored)
│   ├── deps-manifest.sh     writes deps.lock.json
│   ├── lib/verify-backup.sh shared pre-write gate
│   ├── restore-flash.sh
│   └── usb-reset.sh         sysfs unbind/bind recovery
├── tools/mock_backend/      Python mock of the watch API
├── backups/                 gitignored
└── docs/
    ├── hardware-validation.md
    ├── upstream-reference.md  what we learned from NanoClaw / LilyGoLib
    ├── protocol.md            watch <-> backend API
    └── architecture.md
```

Anything that can be expressed without hardware goes in `lib/` so it can be unit
tested natively.

---

## Milestones

Each milestone ends with something flashed on the watch and a checklist in
`docs/hardware-validation.md`. After every hardware-facing change: build,
flash, smoke test.

### M0 — Safety Net and Vendor Baseline

Goal: never lose the ability to recover, and know which hardware works.

1. `scripts/backup-flash.sh`: full 16 MB read of the current factory image to
   `backups/<mac>/factory-<date>.bin`, plus `.sha256` and a `.meta` (MAC, chip,
   flash size, esptool version). Read twice; hashes must match. `backups/` is
   gitignored and mode `0700`, and images are treated as sensitive: once our
   firmware has run, they contain Wi-Fi credentials and the device token.
2. Flash safety, enforced by scripts rather than by convention:
   - One shared routine, `scripts/lib/verify-backup.sh`, which `flash.sh` and
     `restore-flash.sh` both call before **any** write. It reads the connected
     chip's MAC and requires a backup in `backups/<mac>/` whose `.meta` MAC
     matches, whose size is exactly 16 MiB, and whose SHA-256 matches the
     `.sha256` file. Any failure aborts the write.
   - BATS tests cover a missing backup, wrong MAC, truncated image, and edited
     image/hash.
   - `restore-flash.sh` additionally needs typed confirmation, writes with
     esptool verification, then reads back and compares the hash.
   - Restoring a full image also restores NVS (Wi-Fi/settings). That's
     intended: it's a return to that exact state.
   - `scripts/usb-reset.sh` for the stale-USB recovery above.
3. Build and flash **LilyGoLib's `examples/factory` at tag `V0.2.1`**,
   unchanged except for the `platformio.ini`/board/partition settings above.
   Record the exact command and the resulting `.bin` SHA-256.
4. Record PASS / FAIL / NOT TESTED per peripheral in
   `docs/hardware-validation.md`: display, touch, PMIC button, battery,
   charging, RTC, IMU, haptics, speaker, mic, Wi-Fi, BLE init, GPS, LoRa init
   (and identify the radio variant), IR, sleep/wake.
5. Write `docs/upstream-reference.md` from the NanoClaw/LilyGoLib review.
6. Email or open an issue with the NanoClaw author asking for a LICENSE file (optional).

**Done when:** the backup is verified, the factory example runs from our own
build, and the validation table is filled in.

### M1a — Offline Watch (first flash of our own firmware)

Goal: the smallest firmware you can wear all day. No networking.

Scaffold:

- `platformio.ini` with pinned versions (see Pinning policy), board JSON,
  partitions, and a `native` test env.
- `scripts/check.sh`: build + native tests + clang-format check + dependency
  list check. Pre-commit hooks with secret detection.
- `AGENTS.md`, `README.md` (build, flash, recover).

Platform layer (one component per change, flash-tested each time):
power/battery → display/backlight → touch → RTC → IMU → haptics.

Core: event bus, state store, logging with levels.

Features:

- **Watch face**: time, date, battery %, charging.
- **Time**: the RTC stores **UTC**; local time is derived from the POSIX TZ
  string in config (handles DST). If the RTC reports invalid time (oscillator
  stop flag, or year < 2026), show `--:--` and "set time" rather than a
  wrong time.
- **Sleep/wake**: screen timeout, wake on wrist raise/tap (IMU), button, and
  touch. Light sleep while the screen is off.
- **Brightness** in quick settings (swipe down).
- **Launcher** (swipe/tap) with Settings and Diagnostics.
- **Diagnostics**: firmware version and git commit, uptime, free/min heap,
  PSRAM, battery voltage, charge state, RTC/IMU state, last reset reason,
  event-queue drops. Logs min-heap to serial every minute.

**Done when:**

- clean-checkout build works via `scripts/build.sh`
- boots and is fully usable with no `secrets.h` values set
- settings survive a reboot
- sleeps after the timeout and wakes on raise, button, and touch, 20/20 times;
  USB serial reconnects after wake
- every launcher/gesture path reachable and returns home
- charging state correct plugged/unplugged, with the screen on and off
- 8+ hours on wrist without a crash; min-heap flat (±5%) between hour 1 and 8
- battery drain measured and recorded (%/hour, screen-off)

### M1b — Connected Watch

Goal: add network time and the everyday extras.

- **Wi-Fi** platform wrapper and **network worker task** (per the event bus
  contract). Credentials from `secrets.h`; multiple SSIDs.
- **NTP** sync when Wi-Fi is up, written back to the RTC (UTC). Persist
  `last_sync_utc` in NVS. **Clock is trusted** when the RTC is valid *and*
  `last_sync_utc` exists *and* now − `last_sync_utc` is between 0 and 7 days.
  Missing metadata, RTC invalid, or time before the last sync means untrusted
  until the next NTP sync. TLS depends on this in M2. The rule lives in `lib/`
  with native tests (reboot, power loss/RTC invalid, clock going backwards,
  DST boundaries).
- Watch face adds Wi-Fi state and **step count** (BMA423, reset at midnight).
- **Timer/stopwatch** with haptic alert.
- Diagnostics adds RSSI, IP, last NTP sync.

**Done when:**

- time is correct after a cold boot with and without Wi-Fi, and across a
  simulated DST change (set RTC just before the transition)
- Wi-Fi absent, wrong password, and AP dropped mid-session: UI never stalls,
  reconnect with backoff works, no crash
- M1a soak and drain checks re-run with Wi-Fi enabled

### M2 — Homelab Glance

Goal: see homelab health from the wrist.

1. Define `docs/protocol.md` (JSON, `Authorization: Bearer <device token>`).
   Transport profiles:
   - `mock`: plain HTTP, LAN only, against `tools/mock_backend`. Exists only in
     the separate PlatformIO env `twatch-s3-plus-mock` (`-DTRANSPORT_MOCK`).
   - `prod`: the default `twatch-s3-plus` env. HTTPS only, CA certificate
     compiled in (a private homelab CA or the server's issuing CA), hostname
     verified. Requests wait until the clock is trusted (M1b rule); otherwise
     show "time not synced" rather than skipping validation.
   - Enforcement: the HTTP client code is compiled only under
     `TRANSPORT_MOCK`, and in prod a `#error` fires if it's defined. The prod
     client rejects any endpoint not starting with `https://`.
     `scripts/check.sh` builds the prod env and fails if its flags contain
     `TRANSPORT_MOCK`. `flash.sh` flashes the prod env by default and warns
     loudly when flashing mock.

   Endpoints:

   ```text
   GET  /api/v1/status          summary: host counts, alert counts
   GET  /api/v1/hosts           list with health
   GET  /api/v1/hosts/{name}    detail: cpu, ram, gpu, gpu_temp, services
   GET  /api/v1/alerts
   GET  /api/v1/agents
   POST /api/v1/agents/request
   ```

2. `tools/mock_backend/` (Python, stdlib or FastAPI) serving realistic data,
   including failure modes (slow, 500, garbage JSON).
3. Parsers and models in `lib/`, native tested.
4. Screens: homelab summary → host list → host detail. Status-dot complication
   on the watch face.
5. Cache last-known state in storage; mark it **stale** with its age.
6. Poll only while the screen is on (default 15 s), plus one fetch on wake.
   No polling while the screen is off in M2.
7. Real backend: a small homelab service that adapts existing sources
   (Zabbix/LibreNMS/Prometheus, or the existing lab dashboard API) to this
   protocol. It lives in its own repo; the firmware only knows the protocol.

**Done when:** killing the backend never freezes the UI; slow, 500,
malformed, oversized, and out-of-order responses are handled (native tests plus
mock failure modes); stale data is labeled; `prod` rejects wrong-host and
untrusted certificates; and the real backend shows real hosts.

### M3 — Alerts and Haptics

- Alert list (CRITICAL → WARNING → INFO), detail view, source/host/age.
- Background check at a low interval while the screen is off (default 2 min,
  measure the battery cost) to vibrate on new CRITICAL alerts.
- Haptic patterns: INFO single short, WARNING double, CRITICAL strong repeat.
  Can be muted, with quiet hours.
- Acknowledge only if the backend supports it safely.

### M4 — Agent Terminal

- Session list, state, short task text, last response.
- Canned prompts from backend-provided config (not compiled in).
- Command safety classes are enforced **server-side**. The watch also shows
  them:
  - read-only → run immediately
  - low-risk → tap confirm
  - high-risk → hold-to-confirm 3 s with target named ("REBOOT SCAR?")
- No arbitrary shell execution from the watch.

### M5 — Voice

Push-to-talk (on-screen button; not the PMIC key), PDM mic capture to PSRAM,
upload from the network task, backend STT → agent → text response. TTS
playback later.

### M6 — OTA (only after M1–M3 are stable)

**Design gate before any code:** write `docs/ota-design.md` and get explicit
approval. It must decide:

- **Where the signature is checked.** Either Secure Boot v2 (the bootloader
  enforces it; burns eFuses **irreversibly**, and every later flash must be
  signed, including over USB) or signature verification in the app before
  `esp_ota_set_boot_partition` (reversible, but it doesn't protect against
  USB flashing). Neither happens without the owner's explicit sign-off.
- Signing key custody (offline, never in git or CI logs) and the release process.
- Anti-rollback: the version must be greater than the running version.
- Image size ≤ 4 MB slot, verified before download completes.
- Recovery: automatic rollback on failed boot (health check, then
  `esp_ota_mark_app_valid_cancel_rollback`), and USB restore as the last resort.

Then implement: version check, battery threshold (>40% or charging), progress
UI. Tests: unsigned, wrongly signed, older, oversized, and truncated images are
all rejected.

### Experimental / P3

BLE phone bridge (Watch → BLE → Android → Tailscale), GPS features, LoRa
status beacon, IR remote, extra watch faces. Each behind a feature flag;
firmware must run normally with all of them disabled.

---

## Power Management

- The screen-off state is the default. Wi-Fi is off or modem-sleeping while the
  screen is off unless the M3 alert check is running.
- GPS, LoRa, speaker amplifier: power-gated via PMIC when unused.
- Measure, don't guess: record drain per milestone in
  `docs/hardware-validation.md`.

| State | Network activity |
|---|---|
| Screen on | poll visible screen's data, 15 s default |
| Screen off | none (M1b–M2); alert check every ~2 min (M3+) |
| Deep sleep | none |

---

## Security

### Threat model (short)

The watch can be lost or stolen, and its flash is readable over USB (no flash
encryption). Assume anything compiled into it — Wi-Fi password, device token,
CA certificate — can be extracted. Design so that doesn't matter much:

- **One token per watch**, scoped to the watch API only, revocable on the
  backend. Rotating it means updating `secrets.h` and reflashing. A lost watch
  means revoking its token and changing the Wi-Fi password if needed.
- Tokens grant read access plus the M4 action classes. High-risk actions are
  still confirmed and authorized server-side, so a stolen token can't act
  without the backend's policy allowing it.
- Flash backups hold the same secrets: gitignored, `0700`, never uploaded.
- Never log credentials, tokens, or full request headers, at any log level.
- Flash encryption and Secure Boot are considered only in the M6 OTA design.

#### Rules

- No secrets in git. `secrets.h` is gitignored; pre-commit runs secret
  detection. **Never import NanoClaw's `config.h` values.**
- Token auth on every backend request; backend authorizes actions server-side.
  The watch is never the only thing deciding whether an action is allowed.
- Transport: plain HTTP only in the `mock` profile. `prod` is HTTPS with a
  compiled-in CA, hostname check, and a trusted clock (see M2).
- Read-only by default; destructive actions need strong confirmation (M4).
- OTA per the approved M6 design only.

---

## Testing

| Layer | How | When |
|---|---|---|
| `lib/` logic | `pio test -e native` (Unity) | every commit (`scripts/check.sh`, CI) |
| Build | `pio run -e twatch-s3-plus` and `-e twatch-s3-plus-mock` | every commit, CI |
| Format | clang-format check | every commit |
| Hardware | smoke checklist below | every hardware-facing change |
| Soak | 8 h wear with min-heap log | end of each milestone |

Smoke checklist:

```text
[ ] boots, no crash loop (check reset reason)
[ ] display and touch work
[ ] battery % sane, charging detected
[ ] time correct
[ ] Wi-Fi connects (if relevant)
[ ] sleep and wake (button, raise, touch)
```

---

## Agent Rules (to become AGENTS.md)

Before changing code:

1. Read `plan.md`, `AGENTS.md`, and relevant `docs/`.
2. Inspect existing code; don't assume LilyGoLib APIs, look them up in the
   pinned library source.
3. Make the smallest safe change, one concern per change.

Never do without explicit direction:

- replace LilyGoLib or LVGL, or change their pinned versions
- change the partition table or board target
- erase NVS / persistent settings, or flash without a verified backup
- add or change OTA, Wi-Fi provisioning, or the auth model
- add remote shell execution
- copy code from NanoClaw (license pending)

Every task report includes: summary, files changed, behavior changed, build
result, tests run, hardware tests still needed, known limitations, next step.

---

## Open Questions

1. ~~Which LoRa radio is fitted?~~ — **resolved 2026-09-26: SX1262** (radio init passed its chip-ID check with the vendor default flag; see `docs/hardware-validation.md`)
2. Where will the real homelab backend run, and does it adapt the existing lab
   dashboard API or query Zabbix/LibreNMS directly? (before M2 step 7)
3. Does the NanoClaw author add a LICENSE file? (affects D3 only)
4. On-watch Wi-Fi provisioning (captive portal/BLE) — needed, or is
   `secrets.h` enough long-term?

---

## Immediate Next Steps

1. `scripts/backup-flash.sh` → back up and verify the factory image.
2. Scaffold `platformio.ini`, board JSON, partitions, `.gitignore`,
   `secrets.h.example`, pre-commit, and the flash-safety checks in
   `flash.sh`/`restore-flash.sh`.
3. Build and flash LilyGoLib `examples/factory` at `V0.2.1`; fill in hardware
   validation.
4. Start M1a with the platform layer for power/battery and display.
