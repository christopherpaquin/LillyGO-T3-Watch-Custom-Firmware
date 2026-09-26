#!/usr/bin/env bash
set -euo pipefail

# Is the watch reachable, and is it safe to flash? Checks, in order:
#   1. the Espressif USB device is present
#   2. the serial port exists
#   3. the chip answers esptool and reports its MAC
#   4. a verified full-flash backup exists for that MAC
# Exit 0 only if all pass. Does not reset the watch when ESPTOOL_OPTS keeps
# it in download mode.

# shellcheck source=scripts/lib/verify-backup.sh
source "$(dirname "$0")/scripts/lib/verify-backup.sh"

ok() { printf '  ✅ %s\n' "$*"; }
bad() {
  printf '  ❌ %s\n' "$*"
  exit 1
}

main() {
  [[ $# -eq 0 ]] || die 2 "usage: $(basename "$0")"
  echo "Watch health:"

  if command -v lsusb > /dev/null 2>&1; then
    lsusb | grep -qi '303a:' || bad "no Espressif USB device; check the cable"
    ok "USB device present (Espressif 303a)"
  fi
  [[ -e "${WATCH_PORT}" ]] ||
    bad "${WATCH_PORT} missing; try scripts/usb-reset.sh or download mode (hold BOOT, tap RST)"
  ok "serial port ${WATCH_PORT} exists"

  local mac backup
  mac="$(read_connected_mac 2> /dev/null)" ||
    bad "chip not answering on ${WATCH_PORT}; try scripts/usb-reset.sh or download mode"
  ok "chip answers, MAC ${mac}"

  backup="$(require_verified_backup "${mac}" 2> /dev/null)" ||
    bad "no verified backup for ${mac}; run scripts/backup-flash.sh before flashing"
  ok "verified backup: ${backup#"${REPO_ROOT}"/}"
}

main "$@"
