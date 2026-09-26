#!/usr/bin/env bats

load test_helper

setup() { setup_env; }

@test "creates bin, sha256 and meta matching the device flash" {
  run "${SCRIPTS}/backup-flash.sh" --label factory
  [ "$status" -eq 0 ]
  image="${lines[-1]}"
  [[ "${image}" == "${BACKUP_ROOT}/${MAC}/factory-"*.bin ]]
  cmp "${image}" "${STUB_FLASH}"
  grep -q "^mac=${MAC}$" "${image%.bin}.meta"
  grep -q "^size=4096$" "${image%.bin}.meta"
  [ "$(awk '{print $1}' "${image%.bin}.sha256")" = "$(sha256sum "${STUB_FLASH}" | awk '{print $1}')" ]
}

@test "backup files and directories are private" {
  run "${SCRIPTS}/backup-flash.sh"
  [ "$status" -eq 0 ]
  image="${lines[-1]}"
  [ "$(stat -c %a "${image}")" = "600" ]
  [ "$(stat -c %a "${image%.bin}.meta")" = "600" ]
  [ "$(stat -c %a "${BACKUP_ROOT}/${MAC}")" = "700" ]
  [ "$(stat -c %a "${BACKUP_ROOT}")" = "700" ]
}

@test "discards the backup when the two reads differ" {
  export STUB_FLAKY_READ=1
  run "${SCRIPTS}/backup-flash.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"two reads differ"* ]]
  [ -z "$(ls -A "${BACKUP_ROOT}/${MAC}")" ]
}

@test "fails clearly when the watch can't be reached" {
  export STUB_FAIL_READMAC=1
  run "${SCRIPTS}/backup-flash.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not read MAC"* ]]
}

@test "rejects an unsafe label" {
  run "${SCRIPTS}/backup-flash.sh" --label "../evil"
  [ "$status" -eq 2 ]
}
