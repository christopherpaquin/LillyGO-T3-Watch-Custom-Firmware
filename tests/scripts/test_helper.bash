#!/usr/bin/env bash
# Common setup: a temp backup root, a small fake flash, and the stub esptool.

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
SCRIPTS="${REPO_ROOT}/scripts"

setup_env() {
  export BACKUP_ROOT="${BATS_TEST_TMPDIR}/backups"
  export ESPTOOL="${BATS_TEST_DIRNAME}/stubs/esptool"
  export WATCH_PORT="/dev/null"
  export WATCH_FLASH_SIZE=4096
  export STUB_FLASH="${BATS_TEST_TMPDIR}/flash.bin"
  export STUB_MAC="68:ee:8f:48:22:8c"
  export MAC="68ee8f48228c"
  head -c "${WATCH_FLASH_SIZE}" /dev/urandom > "${STUB_FLASH}"
}

# Make a verified backup via the real script; prints its path.
make_backup() {
  "${SCRIPTS}/backup-flash.sh" --label test 2> /dev/null
}
