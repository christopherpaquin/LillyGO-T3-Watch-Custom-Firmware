#!/usr/bin/env bats

load test_helper

setup() {
  setup_env
  export STUB_LOG="${BATS_TEST_TMPDIR}/esptool.log"
  IMAGE="$(make_backup)"
  : > "${STUB_LOG}"
  # Change the "device" so a restore has something to undo.
  head -c "${WATCH_FLASH_SIZE}" /dev/urandom > "${STUB_FLASH}"
}

@test "restores and verifies with --confirm" {
  run "${SCRIPTS}/restore-flash.sh" "${IMAGE}" --confirm "68:EE:8F:48:22:8C"
  [ "$status" -eq 0 ]
  cmp "${IMAGE}" "${STUB_FLASH}"
  grep -q "write-flash" "${STUB_LOG}"
}

@test "refuses without confirmation when not interactive" {
  run "${SCRIPTS}/restore-flash.sh" "${IMAGE}" < /dev/null
  [ "$status" -eq 2 ]
  run grep -q "write-flash" "${STUB_LOG}"
  [ "$status" -ne 0 ]
}

@test "refuses when confirmation names a different MAC" {
  run "${SCRIPTS}/restore-flash.sh" "${IMAGE}" --confirm aabbccddeeff
  [ "$status" -eq 1 ]
  run grep -q "write-flash" "${STUB_LOG}"
  [ "$status" -ne 0 ]
}

@test "refuses an image from a different watch" {
  export STUB_MAC="aa:bb:cc:dd:ee:ff"
  run "${SCRIPTS}/restore-flash.sh" "${IMAGE}" --confirm aabbccddeeff
  [ "$status" -eq 1 ]
  [[ "$output" == *"belongs to"* ]]
  run grep -q "write-flash" "${STUB_LOG}"
  [ "$status" -ne 0 ]
}

@test "refuses a tampered image before writing" {
  printf 'X' | dd of="${IMAGE}" bs=1 seek=10 conv=notrunc status=none
  run "${SCRIPTS}/restore-flash.sh" "${IMAGE}" --confirm "${MAC}"
  [ "$status" -eq 1 ]
  run grep -q "write-flash" "${STUB_LOG}"
  [ "$status" -ne 0 ]
}

@test "fails when read-back doesn't match" {
  export STUB_CORRUPT_WRITE=1
  run "${SCRIPTS}/restore-flash.sh" "${IMAGE}" --confirm "${MAC}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"read-back hash"* ]]
}
