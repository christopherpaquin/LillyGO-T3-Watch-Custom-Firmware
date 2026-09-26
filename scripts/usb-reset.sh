#!/usr/bin/env bash
set -euo pipefail

# Software re-plug of the watch's USB device (Espressif 303a:1001) when the
# CDC link goes stale ("Errno 71 Protocol error"). Needs sudo. If the watch's
# firmware has USB asleep this won't help: wake it, or use download mode
# (hold BOOT, tap RST, release BOOT).

# shellcheck source=scripts/lib/common.sh
source "$(dirname "$0")/lib/common.sh"

VENDOR="303a"
ATTEMPTS="${USB_RESET_ATTEMPTS:-4}"

find_device() {
  local d
  for d in /sys/bus/usb/devices/*; do
    [[ -f "${d}/idVendor" ]] || continue
    if [[ "$(cat "${d}/idVendor")" == "${VENDOR}" ]]; then
      basename "${d}"
      return 0
    fi
  done
  return 1
}

main() {
  [[ $# -eq 0 ]] || die 2 "usage: $(basename "$0")"
  local dev i
  dev="$(find_device)" || die 1 "no Espressif USB device found; check the cable"
  log "re-plugging USB device ${dev}"
  for ((i = 1; i <= ATTEMPTS; i++)); do
    echo "${dev}" | sudo tee /sys/bus/usb/drivers/usb/unbind > /dev/null 2>&1 || true
    sleep 1
    echo "${dev}" | sudo tee /sys/bus/usb/drivers/usb/bind > /dev/null 2>&1 || true
    sleep 3
    if [[ -e "${WATCH_PORT}" ]]; then
      log "OK: ${WATCH_PORT} is back (attempt ${i})"
      return 0
    fi
  done
  die 1 "${WATCH_PORT} did not come back after ${ATTEMPTS} attempts; wake the watch or use download mode (hold BOOT, tap RST)"
}

main "$@"
