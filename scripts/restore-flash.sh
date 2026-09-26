#!/usr/bin/env bash
set -euo pipefail

# Write a full-flash backup back to the watch it came from, then read it back
# and compare. This also restores NVS (Wi-Fi, settings) to that exact state.

# shellcheck source=scripts/lib/verify-backup.sh
source "$(dirname "$0")/lib/verify-backup.sh"

READBACK=""
cleanup() { rm -f "${READBACK}"; }
trap cleanup EXIT

usage() {
  cat << EOF
Usage: $(basename "$0") IMAGE.bin [--confirm MAC]

Restore IMAGE.bin to the watch on ${WATCH_PORT}. Asks you to type the watch's
MAC (12 hex digits, no colons) unless --confirm MAC is given.
EOF
}

main() {
  local image="" confirm=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --confirm)
        [[ $# -ge 2 ]] || die 2 "--confirm needs a MAC"
        confirm="$(normalize_mac "$2")"
        shift 2
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      -*)
        usage >&2
        die 2 "unknown option: $1"
        ;;
      *)
        [[ -z "${image}" ]] || die 2 "only one image may be given"
        image="$1"
        shift
        ;;
    esac
  done
  [[ -n "${image}" ]] || {
    usage >&2
    die 2 "no image given"
  }

  require_cmd "${ESPTOOL}" sha256sum awk stat

  local mac want got
  mac="$(read_connected_mac)"
  verify_backup_image "${image}" "${mac}"
  want="$(sha256_of "${image}")"

  if [[ -z "${confirm}" ]]; then
    [[ -t 0 ]] || die 2 "not interactive; pass --confirm ${mac}"
    log "About to OVERWRITE the entire flash of watch ${mac} with ${image}"
    read -r -p "Type the watch MAC (${mac}) to continue: " confirm
    confirm="$(normalize_mac "${confirm}")"
  fi
  [[ "${confirm}" == "${mac}" ]] || die 1 "confirmation did not match ${mac}; nothing written"

  log "writing ${image}"
  esp write-flash 0 "${image}" >&2 ||
    die 1 "write failed; the watch may be unbootable, retry in download mode"

  READBACK="$(mktemp)"
  log "reading back to verify"
  esp read-flash 0 "${WATCH_FLASH_SIZE}" "${READBACK}" >&2 ||
    die 1 "read-back failed"
  got="$(sha256_of "${READBACK}")"
  [[ "${got}" == "${want}" ]] || die 1 "read-back hash ${got} does not match image ${want}"

  log "OK: restored and verified (sha256 ${want})"
}

main "$@"
