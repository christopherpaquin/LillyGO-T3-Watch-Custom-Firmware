#!/usr/bin/env bash
set -euo pipefail

# Undo install.sh. By default removes only this repo's generated state
# (pre-commit hooks, build output, vendor baseline checkout). Flash backups in
# backups/ are NEVER removed by this script: they are the only way to restore
# a watch, delete them by hand if you really mean to.
#
#   --purge-tools   also pipx-uninstall platformio, esptool, pre-commit
#                   (shared with other projects; off by default)

# shellcheck source=scripts/lib/common.sh
source "$(dirname "$0")/scripts/lib/common.sh"

main() {
  local purge_tools=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --purge-tools)
        purge_tools=1
        shift
        ;;
      -h | --help)
        sed -n '4,11p' "$0"
        exit 0
        ;;
      *) die 2 "unknown argument: $1" ;;
    esac
  done

  if command -v pre-commit > /dev/null 2>&1; then
    (cd "${REPO_ROOT}" && pre-commit uninstall >&2) || log "pre-commit uninstall failed (continuing)"
  fi
  rm -rf "${REPO_ROOT}/.pio" "${REPO_ROOT}/.baseline"
  log "removed build output and vendor baseline checkout"

  if [[ ${purge_tools} -eq 1 ]]; then
    local pkg
    for pkg in platformio esptool pre-commit; do
      pipx uninstall "${pkg}" >&2 || log "${pkg} was not installed via pipx"
    done
    rm -rf "${HOME}/.platformio"
    log "removed PlatformIO tools and ~/.platformio"
  fi

  if [[ -d "${BACKUP_ROOT}" ]]; then
    log "kept flash backups in ${BACKUP_ROOT}"
  fi
  log "OK: uninstalled"
}

main "$@"
