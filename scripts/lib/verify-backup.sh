#!/usr/bin/env bash
# Pre-write gate shared by flash.sh and restore-flash.sh.
#
# verify_backup_image <image.bin> [expected-mac]
#   Checks the image's .sha256 and .meta sidecars, exact flash size, hash, and
#   (if given) that the .meta MAC matches. Returns 0 or dies.
#
# require_verified_backup <mac>
#   Dies unless backups/<mac>/ holds at least one image passing
#   verify_backup_image. Prints the newest verified image path.

# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

meta_value() {
  # meta_value <file.meta> <key>
  awk -F= -v k="$2" '$1 == k { sub(/^[^=]*=/, ""); print; exit }' "$1"
}

verify_backup_image() {
  local image="$1" expected_mac="${2:-}"
  local sha_file="${image%.bin}.sha256" meta_file="${image%.bin}.meta"
  local size want_sha got_sha meta_mac

  [[ -f "${image}" ]] || die 1 "backup image not found: ${image}"
  [[ -f "${sha_file}" ]] || die 1 "missing hash file: ${sha_file}"
  [[ -f "${meta_file}" ]] || die 1 "missing metadata file: ${meta_file}"

  size="$(file_size "${image}")"
  [[ "${size}" == "${WATCH_FLASH_SIZE}" ]] ||
    die 1 "backup ${image} is ${size} bytes, expected ${WATCH_FLASH_SIZE}"

  want_sha="$(awk '{print $1; exit}' "${sha_file}")"
  got_sha="$(sha256_of "${image}")"
  [[ -n "${want_sha}" && "${want_sha}" == "${got_sha}" ]] ||
    die 1 "backup ${image} hash mismatch (file ${got_sha}, recorded ${want_sha:-none})"

  meta_mac="$(normalize_mac "$(meta_value "${meta_file}" mac)")"
  [[ -n "${meta_mac}" ]] || die 1 "metadata ${meta_file} has no mac= entry"
  if [[ -n "${expected_mac}" && "${meta_mac}" != "${expected_mac}" ]]; then
    die 1 "backup ${image} belongs to ${meta_mac}, connected watch is ${expected_mac}"
  fi
  return 0
}

require_verified_backup() {
  local mac="$1" dir image newest=""
  dir="${BACKUP_ROOT}/${mac}"
  [[ -d "${dir}" ]] ||
    die 1 "no backup for watch ${mac} in ${dir}; run scripts/backup-flash.sh first"
  # Newest first; the first one that verifies wins.
  while IFS= read -r image; do
    if (verify_backup_image "${image}" "${mac}") 2> /dev/null; then
      newest="${image}"
      break
    fi
  done < <(ls -1t "${dir}"/*.bin 2> /dev/null)
  [[ -n "${newest}" ]] ||
    die 1 "no verified backup for watch ${mac} in ${dir}; run scripts/backup-flash.sh"
  printf '%s\n' "${newest}"
}
