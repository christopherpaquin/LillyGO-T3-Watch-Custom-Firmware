#!/usr/bin/env bash
set -euo pipefail

# Set up the host development environment for this firmware. Idempotent:
# already-installed tools are left alone.
#   - PlatformIO and esptool (via pipx)
#   - pre-commit hooks for this repo
#   - checks: serial-port access (dialout group), bats, shellcheck

# shellcheck source=scripts/lib/common.sh
source "$(dirname "$0")/scripts/lib/common.sh"

PIPX_TOOLS=(platformio esptool pre-commit)
APT_HINT_TOOLS=(bats shellcheck git)

ensure_pipx_tool() {
  local pkg="$1"
  if pipx list --short 2> /dev/null | awk '{print $1}' | grep -qx "${pkg}"; then
    log "ok: ${pkg} already installed"
  else
    log "installing ${pkg} with pipx"
    pipx install "${pkg}" >&2 || die 1 "pipx install ${pkg} failed"
  fi
}

main() {
  [[ $# -eq 0 ]] || die 2 "usage: $(basename "$0")"
  require_cmd pipx

  local pkg missing=()
  for pkg in "${PIPX_TOOLS[@]}"; do ensure_pipx_tool "${pkg}"; done

  for pkg in "${APT_HINT_TOOLS[@]}"; do
    command -v "${pkg}" > /dev/null 2>&1 || missing+=("${pkg}")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    die 3 "missing system tools: ${missing[*]} (e.g. sudo apt install ${missing[*]})"
  fi

  if ! id -nG | tr ' ' '\n' | grep -qx dialout; then
    log "WARNING: $(id -un) is not in the dialout group; run: sudo usermod -aG dialout $(id -un) and log in again"
  fi

  (cd "${REPO_ROOT}" && pre-commit install >&2) || die 1 "pre-commit install failed"

  if [[ ! -f "${REPO_ROOT}/include/secrets.h" && -f "${REPO_ROOT}/include/secrets.h.example" ]]; then
    install -m 600 "${REPO_ROOT}/include/secrets.h.example" "${REPO_ROOT}/include/secrets.h"
    log "created include/secrets.h from the example; fill in your values"
  fi

  log "OK: environment ready. Next: scripts/backup-flash.sh (once per watch)"
}

main "$@"
