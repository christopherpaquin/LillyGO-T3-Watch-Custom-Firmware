#!/usr/bin/env bash
set -euo pipefail

# Build and upload a PlatformIO env to the watch, but only if a verified
# full-flash backup of *this* watch exists (see scripts/backup-flash.sh).

# shellcheck source=scripts/lib/verify-backup.sh
source "$(dirname "$0")/lib/verify-backup.sh"

PIO="${PIO:-pio}"

usage() {
  cat << EOF
Usage: $(basename "$0") [--project DIR] [--env ENV]

  --project DIR   PlatformIO project directory (default: repo root)
  --env ENV       PlatformIO env to build and upload (default: twatch-s3-plus)

Refuses to write unless backups/<mac>/ holds a verified backup of the
connected watch.
EOF
}

main() {
  local project="${REPO_ROOT}" env="twatch-s3-plus"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project)
        [[ $# -ge 2 ]] || die 2 "--project needs a directory"
        project="$2"
        shift 2
        ;;
      --env)
        [[ $# -ge 2 ]] || die 2 "--env needs a name"
        env="$2"
        shift 2
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        usage >&2
        die 2 "unknown argument: $1"
        ;;
    esac
  done
  [[ -f "${project}/platformio.ini" ]] || die 2 "no platformio.ini in ${project}"
  require_cmd "${ESPTOOL}" "${PIO}" sha256sum awk stat

  local mac backup
  mac="$(read_connected_mac)"
  backup="$(require_verified_backup "${mac}")"
  log "watch ${mac}: verified backup ${backup}"

  if [[ "${env}" == *mock* ]]; then
    log "WARNING: flashing a MOCK transport build (plain HTTP). Not for daily use."
  fi

  log "building and uploading env ${env} from ${project}"
  "${PIO}" run -d "${project}" -e "${env}" -t upload --upload-port "${WATCH_PORT}" >&2 ||
    die 1 "upload failed; if the watch won't boot, enter download mode and use scripts/restore-flash.sh ${backup}"
  # PlatformIO's RTS reset can leave the chip in download mode (DTR still
  # asserted on USB-Serial/JTAG). A watchdog reset always boots the app.
  "${ESPTOOL}" --port "${WATCH_PORT}" --before no-reset --after watchdog-reset read-mac > /dev/null 2>&1 ||
    log "WARNING: couldn't reset the watch; press RST to boot the new firmware"
  log "OK: flashed ${env}"
}

main "$@"
