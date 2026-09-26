#!/usr/bin/env bash
# Shared helpers for the flash/backup scripts. Source, don't execute.
#
# Environment overrides (used by tests and unusual setups):
#   WATCH_PORT        serial port             (default /dev/ttyACM0)
#   ESPTOOL           esptool executable      (default esptool)
#   BACKUP_ROOT       backup directory        (default <repo>/backups)
#   WATCH_FLASH_SIZE  flash size in bytes     (default 16 MiB)
#   ESPTOOL_OPTS      extra esptool options, e.g. "--before no-reset
#                     --after no-reset" to keep a watch in download mode

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WATCH_PORT="${WATCH_PORT:-/dev/ttyACM0}"
ESPTOOL="${ESPTOOL:-esptool}"
BACKUP_ROOT="${BACKUP_ROOT:-${REPO_ROOT}/backups}"
WATCH_FLASH_SIZE="${WATCH_FLASH_SIZE:-16777216}"
read -r -a ESPTOOL_OPTS_ARR <<< "${ESPTOOL_OPTS:-}"

log() { printf '[%s] %s\n' "$(basename "$0")" "$*" >&2; }

# die <exit-code> <message>
die() {
  local code="$1"
  shift
  log "ERROR: $*"
  exit "${code}"
}

require_cmd() {
  local cmd
  for cmd in "$@"; do
    command -v "${cmd}" > /dev/null 2>&1 || die 3 "required command not found: ${cmd}"
  done
}

# esp <command> [args...]: run esptool against the watch port.
esp() { "${ESPTOOL}" --port "${WATCH_PORT}" "${ESPTOOL_OPTS_ARR[@]}" "$@"; }

sha256_of() { sha256sum "$1" | awk '{print $1}'; }

file_size() { stat -c %s "$1"; }

# Normalize "68:EE:8F:48:22:8C" -> "68ee8f48228c"
normalize_mac() { tr -d ':' <<< "$1" | tr '[:upper:]' '[:lower:]'; }

# Print the connected chip's MAC, normalized. Fails if it can't be read.
read_connected_mac() {
  local out mac
  out="$(esp read-mac 2>&1)" ||
    die 1 "could not read MAC from ${WATCH_PORT} (is the watch connected? try scripts/usb-reset.sh or download mode). esptool said: $(tail -n 2 <<< "${out}")"
  mac="$(grep -m1 -oiE 'MAC:[[:space:]]*([0-9a-f]{2}:){5}[0-9a-f]{2}' <<< "${out}" | awk '{print $2}')"
  [[ -n "${mac}" ]] || die 1 "esptool output did not contain a MAC address"
  normalize_mac "${mac}"
}
