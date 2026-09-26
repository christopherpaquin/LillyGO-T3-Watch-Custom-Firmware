#!/usr/bin/env bats

load test_helper

setup() {
  setup_env
  export PIO="${BATS_TEST_DIRNAME}/stubs/pio"
  export PIO_LOG="${BATS_TEST_TMPDIR}/pio.log"
  export STUB_LOG="${BATS_TEST_TMPDIR}/esptool.log"
  PROJECT="${BATS_TEST_TMPDIR}/proj"
  mkdir -p "${PROJECT}"
  touch "${PROJECT}/platformio.ini"
}

@test "refuses to upload without a backup" {
  run "${SCRIPTS}/flash.sh" --project "${PROJECT}" --env demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"no backup for watch"* ]]
  [ ! -s "${PIO_LOG}" ]
}

@test "refuses to upload when the only backup is tampered" {
  image="$(make_backup)"
  printf 'X' | dd of="${image}" bs=1 seek=10 conv=notrunc status=none
  run "${SCRIPTS}/flash.sh" --project "${PROJECT}" --env demo
  [ "$status" -eq 1 ]
  [ ! -s "${PIO_LOG}" ]
}

@test "refuses when the backup is for a different watch" {
  make_backup > /dev/null
  export STUB_MAC="aa:bb:cc:dd:ee:ff"
  run "${SCRIPTS}/flash.sh" --project "${PROJECT}" --env demo
  [ "$status" -eq 1 ]
  [ ! -s "${PIO_LOG}" ]
}

@test "uploads the requested env when a verified backup exists" {
  make_backup > /dev/null
  run "${SCRIPTS}/flash.sh" --project "${PROJECT}" --env demo
  [ "$status" -eq 0 ]
  grep -q -- "-e demo -t upload" "${PIO_LOG}"
  grep -q -- "--after watchdog-reset" "${STUB_LOG}"
}

@test "warns when flashing a mock build" {
  make_backup > /dev/null
  run "${SCRIPTS}/flash.sh" --project "${PROJECT}" --env twatch-s3-plus-mock
  [ "$status" -eq 0 ]
  [[ "$output" == *"MOCK transport"* ]]
}

@test "rejects a directory without platformio.ini" {
  run "${SCRIPTS}/flash.sh" --project "${BATS_TEST_TMPDIR}" --env demo
  [ "$status" -eq 2 ]
}
