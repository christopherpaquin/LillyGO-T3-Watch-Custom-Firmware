#!/usr/bin/env bash
set -euo pipefail

# Read the watch's entire flash twice, keep it only if both reads match.
# Writes backups/<mac>/<label>-<timestamp>.{bin,sha256,meta} with mode 0600.
# Backups contain Wi-Fi credentials and tokens once our firmware has run:
# they are gitignored and must never be uploaded.

# shellcheck source=scripts/lib/common.sh
source "$(dirname "$0")/lib/common.sh"

TMP1=""
TMP2=""
cleanup() { rm -f "${TMP1}" "${TMP2}"; }
trap cleanup EXIT

usage() {
  cat << EOF
Usage: $(basename "$0") [--label NAME]

Back up the full ${WATCH_FLASH_SIZE}-byte flash of the watch on ${WATCH_PORT}.
  --label NAME   filename prefix (default: backup), e.g. "factory"
EOF
}

main() {
  local label="backup"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --label)
        [[ $# -ge 2 && "$2" =~ ^[A-Za-z0-9_-]+$ ]] || die 2 "--label needs a name of [A-Za-z0-9_-]"
        label="$2"
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

  require_cmd "${ESPTOOL}" sha256sum awk stat

  local mac dir stamp base sha1 sha2
  mac="$(read_connected_mac)"
  umask 077
  dir="${BACKUP_ROOT}/${mac}"
  mkdir -p "${dir}"
  chmod 700 "${BACKUP_ROOT}" "${dir}"

  TMP1="$(mktemp "${dir}/.read1.XXXXXX")"
  TMP2="$(mktemp "${dir}/.read2.XXXXXX")"

  log "watch ${mac}: reading flash (pass 1/2)"
  esp read-flash 0 "${WATCH_FLASH_SIZE}" "${TMP1}" >&2 ||
    die 1 "flash read (pass 1) failed"
  log "reading flash (pass 2/2)"
  esp read-flash 0 "${WATCH_FLASH_SIZE}" "${TMP2}" >&2 ||
    die 1 "flash read (pass 2) failed"

  [[ "$(file_size "${TMP1}")" == "${WATCH_FLASH_SIZE}" ]] ||
    die 1 "pass 1 returned $(file_size "${TMP1}") bytes, expected ${WATCH_FLASH_SIZE}"
  sha1="$(sha256_of "${TMP1}")"
  sha2="$(sha256_of "${TMP2}")"
  [[ "${sha1}" == "${sha2}" ]] ||
    die 1 "the two reads differ (${sha1} vs ${sha2}); USB link unreliable, backup discarded"

  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  base="${dir}/${label}-${stamp}"
  mv "${TMP1}" "${base}.bin"
  printf '%s  %s\n' "${sha1}" "$(basename "${base}.bin")" > "${base}.sha256"
  {
    printf 'mac=%s\n' "${mac}"
    printf 'size=%s\n' "${WATCH_FLASH_SIZE}"
    printf 'created_utc=%s\n' "${stamp}"
    printf 'esptool=%s\n' "$("${ESPTOOL}" version 2> /dev/null | tail -n 1)"
  } > "${base}.meta"
  chmod 600 "${base}.bin" "${base}.sha256" "${base}.meta"

  log "OK: ${base}.bin (sha256 ${sha1})"
  printf '%s\n' "${base}.bin"
}

main "$@"
